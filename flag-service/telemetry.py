"""OpenTelemetry setup shared by the independently built Python services.

OTLP/HTTP exports all three signals to OTEL_EXPORTER_OTLP_ENDPOINT. Application
logs also keep JSON stdout for kubectl; collection must deduplicate this path.
"""

import json
import logging
import os
import socket
import time
from datetime import UTC, datetime

from flask import g, request
from opentelemetry import metrics, trace
from opentelemetry._logs import set_logger_provider
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.logging.handler import LoggingHandler
from opentelemetry.sdk._logs import LoggerProvider
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor


class JsonLogFormatter(logging.Formatter):
    """Keep trace identifiers in stdout without capturing headers or bodies."""

    def __init__(self, service_name):
        super().__init__()
        self.service_name = service_name

    def format(self, record):
        span = trace.get_current_span().get_span_context()
        payload = {
            "timestamp": datetime.fromtimestamp(record.created, UTC).isoformat(),
            "severity": record.levelname,
            "service.name": self.service_name,
            "logger": record.name,
            "message": record.getMessage(),
            "otel_exported": record.name in {"app", "__main__", "togglemaster.http"}
            and record.levelno >= logging.INFO,
        }
        if span.is_valid:
            payload.update(trace_id=f"{span.trace_id:032x}", span_id=f"{span.span_id:016x}")
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False)


class Telemetry:
    def __init__(self, service_name, tracer_provider, meter_provider, *, enabled=True):
        self.enabled = enabled
        self.tracer_provider = tracer_provider
        self.meter_provider = meter_provider
        self.tracer = tracer_provider.get_tracer(f"togglemaster.{service_name}")
        self.meter = meter_provider.get_meter("togglemaster.application", "1.0")

    def instrument_flask(self, app):
        if not self.enabled:
            return
        FlaskInstrumentor().instrument_app(
            app, tracer_provider=self.tracer_provider, meter_provider=self.meter_provider,
        )
        requests = self.meter.create_counter("app.http.requests", unit="{request}")
        duration = self.meter.create_histogram("app.http.duration", unit="s")
        log = logging.getLogger("togglemaster.http")

        @app.before_request
        def start_timer():
            g.otel_request_started = time.perf_counter()

        @app.after_request
        def record_response(response):
            # Route templates bound cardinality; never use user IDs or raw URLs.
            route = request.url_rule.rule if request.url_rule else "unmatched"
            attributes = {
                "http.route": route,
                "http.request.method": request.method,
                "http.response.status_code": response.status_code,
                "app.request.kind": "health" if route == "/health" else "business",
            }
            requests.add(1, attributes)
            duration.record(time.perf_counter() - g.otel_request_started, attributes)
            log.info("HTTP request completed", extra=attributes)
            return response

    def instrument_requests(self):
        if self.enabled:
            from opentelemetry.instrumentation.requests import RequestsInstrumentor
            RequestsInstrumentor().instrument(
                tracer_provider=self.tracer_provider, meter_provider=self.meter_provider,
            )

    def instrument_postgres(self):
        if self.enabled:
            from opentelemetry.instrumentation.psycopg2 import Psycopg2Instrumentor
            Psycopg2Instrumentor().instrument(tracer_provider=self.tracer_provider)


def configure_telemetry(service_name):
    """Initialize in each Gunicorn worker (do not use --preload)."""
    if os.getenv("OTEL_SDK_DISABLED", "false").lower() == "true":
        return Telemetry(service_name, trace.NoOpTracerProvider(), metrics.NoOpMeterProvider(), enabled=False)

    resource = Resource.create({
        "service.name": service_name,
        "service.namespace": "togglemaster",
        "service.instance.id": f"{socket.gethostname()}:{os.getpid()}",
        "deployment.environment.name": os.getenv("DEPLOYMENT_ENVIRONMENT", "dev"),
    })
    tracer_provider = TracerProvider(resource=resource)
    tracer_provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
    trace.set_tracer_provider(tracer_provider)

    meter_provider = MeterProvider(resource=resource, metric_readers=[
        PeriodicExportingMetricReader(OTLPMetricExporter()),
    ])
    metrics.set_meter_provider(meter_provider)

    logger_provider = LoggerProvider(resource=resource)
    logger_provider.add_log_record_processor(BatchLogRecordProcessor(OTLPLogExporter()))
    set_logger_provider(logger_provider)
    handler = LoggingHandler(level=logging.INFO, logger_provider=logger_provider)
    # Avoid feeding exporter diagnostics back into the same exporter.
    for name in ("app", "__main__", "togglemaster.http"):
        logging.getLogger(name).addHandler(handler)
    for stream_handler in logging.getLogger().handlers:
        stream_handler.setFormatter(JsonLogFormatter(service_name))
    return Telemetry(service_name, tracer_provider, meter_provider)
