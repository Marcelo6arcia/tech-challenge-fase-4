"""Behavioral checks for trace propagation, low-cardinality metrics and log correlation."""

import json
import logging

from flask import Flask
from opentelemetry import trace
from opentelemetry.instrumentation.logging.handler import LoggingHandler
from opentelemetry.sdk._logs import LoggerProvider
from opentelemetry.sdk._logs.export import InMemoryLogRecordExporter, SimpleLogRecordProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import InMemoryMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter

from telemetry import JsonLogFormatter, Telemetry, configure_telemetry

TRACE_ID = "0123456789abcdef0123456789abcdef"
PARENT_ID = "0123456789abcdef"


def test_disabled_sdk_does_not_start_exporters(monkeypatch):
    monkeypatch.setenv("OTEL_SDK_DISABLED", "true")
    configured = configure_telemetry("test-service")
    assert not configured.enabled
    assert isinstance(configured.tracer_provider, trace.NoOpTracerProvider)
    with configured.tracer.start_as_current_span("test") as span:
        assert not span.is_recording()


def test_http_keeps_parent_and_records_route_status_and_health_kind(monkeypatch):
    monkeypatch.setenv("OTEL_SDK_DISABLED", "false")
    exporter = InMemorySpanExporter()
    provider = TracerProvider(resource=Resource({"service.name": "test-service"}))
    provider.add_span_processor(SimpleSpanProcessor(exporter))
    reader = InMemoryMetricReader()
    meter_provider = MeterProvider(metric_readers=[reader], resource=Resource({}))
    telemetry = Telemetry("test-service", provider, meter_provider)
    app = Flask("telemetry-test")
    telemetry.instrument_flask(app)
    app.add_url_rule("/flags/<name>", view_func=lambda name: ("failed", 503))
    app.add_url_rule("/health", endpoint="health", view_func=lambda: "ok")
    client = app.test_client()
    response = client.get("/flags/private-name", headers={
        "traceparent": f"00-{TRACE_ID}-{PARENT_ID}-01",
    })
    assert response.status_code == 503
    client.get("/health")
    server = next(
        span for span in exporter.get_finished_spans() if span.attributes.get("http.route") == "/flags/<name>"
    )
    assert server.context.trace_id == int(TRACE_ID, 16)
    assert server.parent.span_id == int(PARENT_ID, 16)
    assert server.status.status_code == trace.StatusCode.ERROR
    metrics = {
        metric.name: metric
        for resource in reader.get_metrics_data().resource_metrics
        for scope in resource.scope_metrics for metric in scope.metrics
    }
    points = metrics["app.http.requests"].data.data_points
    assert {(p.attributes["http.route"], p.attributes["http.response.status_code"], p.value) for p in points} == {
        ("/flags/<name>", 503, 1), ("/health", 200, 1),
    }
    assert {p.attributes["app.request.kind"] for p in points} == {"business", "health"}
    assert metrics["app.http.duration"].unit == "s"
    assert all(p.sum >= 0 for p in metrics["app.http.duration"].data.data_points)
    provider.shutdown()
    meter_provider.shutdown()


def test_otlp_and_stdout_logs_keep_the_active_trace(monkeypatch):
    monkeypatch.setenv("OTEL_SDK_DISABLED", "false")
    resource = Resource({"service.name": "test-service"})
    provider = TracerProvider(resource=resource)
    logs = InMemoryLogRecordExporter()
    logger_provider = LoggerProvider(resource=resource)
    logger_provider.add_log_record_processor(SimpleLogRecordProcessor(logs))
    handler = LoggingHandler(logger_provider=logger_provider)
    with provider.get_tracer("test").start_as_current_span("message") as span:
        record = logging.LogRecord("app", logging.INFO, __file__, 1, "completed", (), None)
        handler.handle(record)
        stdout = json.loads(JsonLogFormatter("test-service").format(record))
        assert stdout["trace_id"] == f"{span.get_span_context().trace_id:032x}"
        assert stdout["span_id"] == f"{span.get_span_context().span_id:016x}"
        assert stdout["otel_exported"] is True
    exported = logs.get_finished_logs()[0].log_record
    assert exported.trace_id == int(stdout["trace_id"], 16)
    assert exported.span_id == int(stdout["span_id"], 16)
    diagnostic = logging.LogRecord("opentelemetry.exporter", logging.ERROR, __file__, 1, "export failed", (), None)
    assert json.loads(JsonLogFormatter("test-service").format(diagnostic))["otel_exported"] is False
    provider.shutdown()
    logger_provider.shutdown()
