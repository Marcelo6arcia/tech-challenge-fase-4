"""SQS tests use in-memory exporters; they never call AWS or a Collector."""

import json
import logging

import pytest
from botocore.exceptions import ClientError
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

import app
from telemetry import Telemetry

TRACE_ID = "0123456789abcdef0123456789abcdef"
PARENT_ID = "0123456789abcdef"


@pytest.fixture
def observed(monkeypatch):
    monkeypatch.setenv("OTEL_SDK_DISABLED", "false")
    resource = Resource({"service.name": "analytics-service"})
    traces = InMemorySpanExporter()
    provider = TracerProvider(resource=resource)
    provider.add_span_processor(SimpleSpanProcessor(traces))
    metrics = InMemoryMetricReader()
    meter_provider = MeterProvider(metric_readers=[metrics], resource=resource)
    telemetry = Telemetry("analytics-service", provider, meter_provider)
    monkeypatch.setattr(app, "telemetry", telemetry)
    monkeypatch.setattr(app, "messages_processed", telemetry.meter.create_counter("app.messages.processed"))
    monkeypatch.setattr(app, "messages_errors", telemetry.meter.create_counter("app.messages.errors"))
    logs = InMemoryLogRecordExporter()
    logger_provider = LoggerProvider(resource=resource)
    logger_provider.add_log_record_processor(SimpleLogRecordProcessor(logs))
    handler = LoggingHandler(logger_provider=logger_provider)
    app.log.addHandler(handler)
    old_level = app.log.level
    app.log.setLevel(logging.INFO)
    yield traces, metrics, logs
    app.log.removeHandler(handler)
    app.log.setLevel(old_level)
    provider.shutdown()
    meter_provider.shutdown()
    logger_provider.shutdown()


def message(parent=True):
    value = {
        "MessageId": "message-1", "ReceiptHandle": "receipt-1",
        "Body": json.dumps({"user_id": "user-1", "flag_name": "flag-1", "result": True, "timestamp": "2026-11-09"}),
    }
    if parent:
        value["MessageAttributes"] = {
            "traceparent": {"DataType": "String", "StringValue": f"00-{TRACE_ID}-{PARENT_ID}-01"},
            "tracestate": {"DataType": "String", "StringValue": "vendor=value"},
        }
    return value


def test_consumer_continues_go_parent_with_database_child_and_correlated_logs(observed, dynamodb_client, sqs_client):
    traces, _, logs = observed
    app.process_message(message())
    spans = traces.get_finished_spans()
    consumer = next(span for span in spans if span.kind == trace.SpanKind.CONSUMER)
    assert consumer.context.trace_id == int(TRACE_ID, 16)
    assert consumer.parent.span_id == int(PARENT_ID, 16)
    assert consumer.context.trace_state.get("vendor") == "value"
    assert consumer.attributes["messaging.system"] == "aws_sqs"
    database = next(span for span in spans if span.name == "DynamoDB PutItem")
    assert database.parent.span_id == consumer.context.span_id
    assert database.kind == trace.SpanKind.CLIENT
    assert all(log.log_record.trace_id == consumer.context.trace_id for log in logs.get_finished_logs())
    sqs_client.delete_message.assert_called_once()
    assert not trace.get_current_span().get_span_context().is_valid


def test_message_without_context_starts_new_trace_not_previous_message(observed, dynamodb_client, sqs_client):
    traces, _, _ = observed
    app.process_message(message())
    app.process_message(message(parent=False))
    consumers = [span for span in traces.get_finished_spans() if span.kind == trace.SpanKind.CONSUMER]
    assert consumers[1].parent is None
    assert consumers[1].context.trace_id != consumers[0].context.trace_id


def test_dynamodb_failure_marks_error_does_not_ack_and_counts_error(observed, dynamodb_client, sqs_client):
    traces, metrics, _ = observed
    dynamodb_client.put_item.side_effect = ClientError({"Error": {"Code": "Unavailable"}}, "PutItem")
    try:
        app.process_message(message())
    finally:
        dynamodb_client.put_item.side_effect = None
    sqs_client.delete_message.assert_not_called()
    consumer = next(span for span in traces.get_finished_spans() if span.kind == trace.SpanKind.CONSUMER)
    assert consumer.status.status_code == trace.StatusCode.ERROR
    assert consumer.attributes["error.type"] == "ClientError"
    points = [
        point for resource in metrics.get_metrics_data().resource_metrics for scope in resource.scope_metrics
        for metric in scope.metrics if metric.name == "app.messages.errors" for point in metric.data.data_points
    ]
    assert sum(point.value for point in points) == 1


def test_worker_requests_trace_attributes(monkeypatch):
    # Stop after observing one long poll, without a running background thread.
    class StopPolling(BaseException):
        pass

    def receive(**kwargs):
        assert kwargs["MessageAttributeNames"] == ["traceparent", "tracestate"]
        raise StopPolling

    monkeypatch.setattr(app.sqs_client, "receive_message", receive)
    with pytest.raises(StopPolling):
        app.sqs_worker_loop()
