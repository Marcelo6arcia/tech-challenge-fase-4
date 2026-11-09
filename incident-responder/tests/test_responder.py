import json
import sys
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from http.server import ThreadingHTTPServer
from pathlib import Path
from unittest.mock import Mock, patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from responder import ANNOTATION, Kubernetes, Ledger, Runbook, handler_factory  # noqa: E402

NOW = 1794222000


def payload(status="firing", service="auth-service", starts=NOW):
    return {"alerts": [{"status": status, "fingerprint": "abc123",
                        "startsAt": datetime.fromtimestamp(starts, timezone.utc).isoformat(),
                        "labels": {"alertname": "AuthHigh5xx", "namespace": "togglemaster",
                                   "service": service}}]}


class ResponderTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / "actions.db"
        self.ledger = Ledger(self.path, now=lambda: NOW)
        self.kube = Mock()
        self.kube.restart.return_value = 2
        self.runbook = Runbook(self.ledger, self.kube, now=lambda: NOW,
                               launch=lambda fn, event: fn(event))

    def test_firing_restarts_once_and_logs_rollout_not_business_recovery(self):
        first = self.runbook.accept(payload())[0]
        self.assertEqual(first["status"], "accepted")
        self.assertEqual(self.runbook.accept(payload())[0]["status"], "duplicate")
        self.kube.restart.assert_called_once_with(first["episode"])
        self.kube.wait_for_rollout.assert_called_once_with(2, first["episode"])
        with self.ledger.connection() as db:
            self.assertEqual(db.execute("SELECT state FROM actions").fetchone()[0], "rollout_completed")

    def test_resolved_and_other_targets_cannot_restart(self):
        for item in [payload("resolved"), payload(service="flag-service")]:
            self.runbook.accept(item)
        self.kube.restart.assert_not_called()

    def test_stale_and_future_events_cannot_restart(self):
        for start in [NOW - 1801, NOW + 61]:
            self.assertEqual(self.runbook.accept(payload(starts=start))[0]["status"], "ignored_stale")
        self.kube.restart.assert_not_called()

    def test_resolved_before_late_firing_blocks_replay_after_reopening(self):
        self.runbook.accept(payload("resolved"))
        reopened = Runbook(Ledger(self.path, now=lambda: NOW), self.kube,
                           now=lambda: NOW, launch=lambda fn, event: fn(event))
        self.assertEqual(reopened.accept(payload())[0]["status"], "duplicate")
        self.kube.restart.assert_not_called()
        # Um novo episódio não é bloqueado pelo cooldown de uma resolução.
        self.assertEqual(reopened.accept(payload(starts=NOW + 1))[0]["status"], "accepted")
        self.kube.restart.assert_called_once()

    def test_mixed_resolved_and_firing_batch_does_not_restart(self):
        item = payload()
        item["alerts"].extend(payload("resolved")["alerts"])
        self.assertEqual(self.runbook.accept(item)[0]["status"], "duplicate")
        self.kube.restart.assert_not_called()

    def test_invalid_later_alert_cannot_cause_partial_action(self):
        item = payload()
        item["alerts"].append(None)
        with self.assertRaises(ValueError):
            self.runbook.accept(item)
        self.kube.restart.assert_not_called()
        with self.ledger.connection() as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM actions").fetchone()[0], 0)

    def test_invalid_shape_and_missing_timestamp(self):
        for item in [{}, {"alerts": [None]}, {"alerts": "bad"}, {"alerts": [payload()["alerts"][0]] * 21}]:
            with self.assertRaises(ValueError):
                self.runbook.accept(item)
        item = payload()
        item["alerts"][0].pop("startsAt")
        with self.assertRaises(ValueError):
            self.runbook.accept(item)
        self.kube.restart.assert_not_called()

    def test_dedup_survives_reopening_database(self):
        self.runbook.accept(payload())
        reopened = Runbook(Ledger(self.path, now=lambda: NOW), self.kube, now=lambda: NOW)
        self.assertEqual(reopened.accept(payload())[0]["status"], "duplicate")
        self.assertEqual(self.kube.restart.call_count, 1)

    def test_new_episode_obeys_cooldown(self):
        self.runbook.accept(payload())
        self.assertEqual(self.runbook.accept(payload(starts=NOW + 1))[0]["status"], "cooldown")
        self.assertEqual(self.kube.restart.call_count, 1)

    def test_concurrent_delivery_cannot_schedule_duplicate_restart(self):
        launch = Mock()
        runbook = Runbook(self.ledger, self.kube, now=lambda: NOW, launch=launch)
        with ThreadPoolExecutor(max_workers=8) as executor:
            results = list(executor.map(lambda _: runbook.accept(payload())[0]["status"], range(8)))
        self.assertEqual(results.count("accepted"), 1)
        self.assertEqual(results.count("duplicate"), 7)
        launch.assert_called_once()

    def test_failure_is_audited_without_retry_or_secret_exception_text(self):
        self.kube.restart.side_effect = RuntimeError("sensitive-value")
        with self.assertLogs("incident-responder", level="INFO") as logs:
            self.runbook.accept(payload())
        self.assertNotIn("sensitive-value", " ".join(logs.output))
        self.assertIn("runbook_failed", " ".join(logs.output))
        self.assertEqual(self.runbook.accept(payload())[0]["status"], "duplicate")
        self.kube.restart.assert_called_once()

    def test_kubernetes_restart_uses_resource_version_and_fixed_annotation(self):
        kube = Kubernetes.__new__(Kubernetes)
        kube.request = Mock(side_effect=[
            {"metadata": {"resourceVersion": "123"}, "spec": {"replicas": 2}},
            {"metadata": {"generation": 8}},
        ])
        self.assertEqual(kube.restart("episode-1"), 8)
        kube.request.assert_called_with("PATCH", {
            "metadata": {"resourceVersion": "123"},
            "spec": {"template": {"metadata": {"annotations": {ANNOTATION: "episode-1"}}}},
        })

    def test_kubernetes_paused_or_scaled_to_zero_cannot_restart(self):
        for spec in [{"paused": True}, {"replicas": 0}]:
            kube = Kubernetes.__new__(Kubernetes)
            kube.request = Mock(return_value={"spec": spec})
            with self.assertRaises(ValueError):
                kube.restart("episode-1")
            kube.request.assert_called_once_with()

    def test_rollout_requires_matching_episode_and_generation(self):
        complete = {
            "metadata": {"generation": 8},
            "spec": {"replicas": 2, "template": {"metadata": {"annotations": {ANNOTATION: "episode-1"}}}},
            "status": {"observedGeneration": 8, "replicas": 2, "updatedReplicas": 2,
                       "readyReplicas": 2, "availableReplicas": 2},
        }
        kube = Kubernetes.__new__(Kubernetes)
        kube.request = Mock(return_value=complete)
        kube.wait_for_rollout(8, "episode-1")
        for generation, episode in [(7, "episode-1"), (8, "other-episode")]:
            with self.assertRaisesRegex(ValueError, "rollout_superseded"):
                kube.wait_for_rollout(generation, episode)
        incomplete = json.loads(json.dumps(complete))
        incomplete["status"]["updatedReplicas"] = 1
        kube.request.return_value = incomplete
        with patch("responder.time.monotonic", side_effect=[0, 0, 181]), patch("responder.time.sleep"):
            with self.assertRaises(TimeoutError):
                kube.wait_for_rollout(8, "episode-1")

    def test_http_authorization_and_accepted_event(self):
        token = "test-only-" + "x" * 32
        server = ThreadingHTTPServer(("127.0.0.1", 0), handler_factory(self.runbook, token))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        url = f"http://127.0.0.1:{server.server_port}/webhook"
        body = json.dumps(payload()).encode()
        with self.assertRaises(HTTPError) as error:
            urlopen(Request(url, data=body), timeout=5)
        self.assertEqual(error.exception.code, 401)
        self.kube.restart.assert_not_called()
        malformed_auth = Request(url, data=body, headers={"Authorization": "Bearer inv\u00e1lido"})
        with self.assertRaises(HTTPError) as error:
            urlopen(malformed_auth, timeout=5)
        self.assertEqual(error.exception.code, 401)
        request = Request(url, data=body, headers={"Authorization": "Bearer " + token})
        with urlopen(request, timeout=5) as response:
            self.assertEqual(response.status, 202)
            self.assertEqual(json.load(response)["actions"][0]["status"], "accepted")


if __name__ == "__main__":
    unittest.main()
