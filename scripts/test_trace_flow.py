"""Trace discovery and evidence contracts; no containers or external services."""

from email.message import Message
import importlib.util
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch
from urllib.error import HTTPError, URLError

import demo

spec = importlib.util.spec_from_file_location("local_smoke", Path(__file__).with_name("local-smoke.py"))
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)

TRACE_ID = "0123456789abcdef0123456789abcdef"


def response_headers(trace_id=TRACE_ID):
    headers = Message()
    headers["x-trace-id"] = trace_id
    headers["Set-Cookie"] = "must-not-be-returned"
    return headers


class HTTPResponse(io.BytesIO):
    def __init__(self, body):
        super().__init__(body)
        self.status = 200
        self.headers = response_headers()


class HTTPContractTests(unittest.TestCase):
    def test_default_and_opt_in_on_success_and_invalid_json(self):
        for opt_in in (False, True):
            for body, expected in ((b'{"ok": true}', {"ok": True}), (b'invalid', {}), (b'[]', {})):
                with self.subTest(opt_in=opt_in, body=body):
                    opener = Mock()
                    opener.open.return_value = HTTPResponse(body)
                    with patch.object(demo, "build_opener", return_value=opener):
                        result = demo.http_json("http://127.0.0.1/test", return_trace_id=opt_in)
                    self.assertEqual(result, (200, expected, TRACE_ID) if opt_in else (200, expected))

    def test_default_and_opt_in_on_http_and_network_errors(self):
        for opt_in in (False, True):
            errors = (
                (HTTPError("http://127.0.0.1/test", 503, "unavailable", response_headers(),
                           io.BytesIO(b'{"error": true}')), (503, {"error": True}), TRACE_ID),
                (URLError("offline"), (0, {}), ""),
            )
            for error, expected, trace_id in errors:
                with self.subTest(opt_in=opt_in, error=type(error).__name__):
                    opener = Mock()
                    opener.open.side_effect = error
                    with patch.object(demo, "build_opener", return_value=opener):
                        result = demo.http_json("http://127.0.0.1/test", return_trace_id=opt_in)
                    self.assertEqual(result, expected + (trace_id,) if opt_in else expected)


class EvaluationTests(unittest.TestCase):
    def test_discovers_server_trace_without_sending_synthetic_parent(self):
        target = SimpleNamespace(state_file=Path("unused"), request=Mock(
            return_value=(200, {"flag_name": "test-flag", "result": True}, TRACE_ID.upper())))
        with patch.object(demo, "write_json") as save:
            state = demo.evaluate(target, {"user_id": "test-user", "flag_name": "test-flag"})
        self.assertEqual(state["trace_id"], TRACE_ID)
        self.assertEqual(state["parent_span_id"], "")
        self.assertNotIn("traceparent", target.request.call_args.kwargs)
        self.assertTrue(target.request.call_args.kwargs["return_trace_id"])
        save.assert_called_once()

    def test_missing_invalid_and_zero_trace_ids_fail_without_saving(self):
        for trace_id in ("", "*" * 32, "0" * 32, TRACE_ID + "\n"):
            with self.subTest(trace_id=trace_id):
                target = SimpleNamespace(state_file=Path("unused"), request=Mock(
                    return_value=(200, {"flag_name": "test-flag", "result": True}, trace_id)))
                with patch.object(demo, "write_json") as save, self.assertRaises(demo.DemoError):
                    demo.evaluate(target, {"user_id": "test-user", "flag_name": "test-flag"})
                save.assert_not_called()


class RootEvidenceTests(unittest.TestCase):
    def evidence(self, *, root_parent="", consumer_parent="0000000000000005"):
        records = [
            ("evaluation-service", "0000000000000001", root_parent, 2),
            ("flag-service", "0000000000000002", "0000000000000001", 2),
            ("targeting-service", "0000000000000003", "0000000000000001", 2),
            ("auth-service", "0000000000000004", "0000000000000002", 2),
            ("evaluation-service", "0000000000000005", "0000000000000001", 4),
            ("analytics-service", "0000000000000006", consumer_parent, 5),
        ]
        resources = [{
            "resource": {"attributes": [{"key": "service.name", "value": {"stringValue": service}}]},
            "scopeSpans": [{"spans": [{"traceId": TRACE_ID, "spanId": span_id,
                                       "parentSpanId": parent, "kind": kind}]}],
        } for service, span_id, parent, kind in records]
        with tempfile.TemporaryDirectory(prefix="fiap-trace-test-") as directory:
            path = Path(directory) / "traces.json"
            path.write_text(json.dumps({"resourceSpans": resources}) + "\n")
            return smoke.trace_evidence(path, TRACE_ID)

    def test_accepts_real_root_with_five_services_and_producer_parent(self):
        evidence = self.evidence()
        self.assertEqual(evidence["services"], sorted(demo.SERVICES))
        self.assertTrue(evidence["evaluation_server_is_root"])
        self.assertTrue(evidence["analytics_consumer_parent_is_producer"])

    def test_rejects_synthetic_parent_or_disconnected_consumer(self):
        self.assertIsNone(self.evidence(root_parent="1111111111111111"))
        self.assertIsNone(self.evidence(consumer_parent="1111111111111111"))
        self.assertIsNone(self.evidence(consumer_parent="0000000000000001"))


if __name__ == "__main__":
    unittest.main()
