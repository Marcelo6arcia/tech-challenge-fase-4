"""Runbook HTTP: um restart limitado por episódio do alerta AuthHigh5xx.

Não executa shell nem aceita namespace/deployment arbitrários do webhook.
O banco SQLite em PVC preserva deduplicação após restart do próprio runbook.
"""

import hashlib
import hmac
import json
import logging
import os
import sqlite3
import ssl
import threading
import time
from contextlib import contextmanager
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

LOG = logging.getLogger("incident-responder")
TARGET_NAMESPACE = "togglemaster"
TARGET_DEPLOYMENT = "auth-service"
ANNOTATION = "fiap.dev/incident-restart"
MAX_BODY = 65536


def audit(event, **fields):
    LOG.info(json.dumps({"event": event, **fields}, sort_keys=True))


class Ledger:
    def __init__(self, path, cooldown=600, now=time.time):
        self.path, self.cooldown, self.now = str(path), cooldown, now
        Path(self.path).parent.mkdir(parents=True, exist_ok=True)
        with self.connection() as db:
            db.execute("CREATE TABLE IF NOT EXISTS actions "
                       "(episode TEXT PRIMARY KEY, accepted REAL, state TEXT)")

    @contextmanager
    def connection(self):
        db = sqlite3.connect(self.path, timeout=10)
        try:
            with db:
                yield db
        finally:
            db.close()

    def claim(self, episode):
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            if db.execute("SELECT 1 FROM actions WHERE episode=?", (episode,)).fetchone():
                return "duplicate"
            last = db.execute("SELECT MAX(accepted) FROM actions").fetchone()[0]
            if last is not None and self.now() - last < self.cooldown:
                return "cooldown"
            db.execute("INSERT INTO actions VALUES (?, ?, 'accepted')", (episode, self.now()))
        return "accepted"

    def record(self, episode, state):
        with self.connection() as db:
            db.execute("UPDATE actions SET state=? WHERE episode=?", (state, episode))

    def resolve(self, episode):
        # A resolução pode chegar antes de um firing atrasado. O tombstone
        # impede essa ação tardia sem consumir o cooldown de uma ação real.
        with self.connection() as db:
            db.execute("INSERT OR IGNORE INTO actions VALUES (?, NULL, 'resolved')", (episode,))


class Kubernetes:
    def __init__(self):
        self.base = "https://kubernetes.default.svc"
        self.path = f"/apis/apps/v1/namespaces/{TARGET_NAMESPACE}/deployments/{TARGET_DEPLOYMENT}"
        self.token_file = Path("/var/run/secrets/kubernetes.io/serviceaccount/token")
        self.context = ssl.create_default_context(
            cafile="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt")

    def request(self, method="GET", payload=None):
        # Relê o token projetado a cada chamada para respeitar sua rotação.
        headers = {"Authorization": "Bearer " + self.token_file.read_text().strip()}
        body = None
        if payload is not None:
            body = json.dumps(payload).encode()
            headers["Content-Type"] = "application/merge-patch+json"
        request = Request(self.base + self.path, data=body, headers=headers, method=method)
        with urlopen(request, context=self.context, timeout=10) as response:
            return json.load(response)

    def restart(self, episode):
        before = self.request()
        if before.get("spec", {}).get("paused") or before.get("spec", {}).get("replicas", 1) < 1:
            raise ValueError("deployment_paused_or_scaled_to_zero")
        updated = self.request("PATCH", {
            "metadata": {"resourceVersion": before["metadata"]["resourceVersion"]},
            "spec": {"template": {"metadata": {"annotations": {ANNOTATION: episode}}}}
        })
        return updated["metadata"]["generation"]

    def wait_for_rollout(self, generation, episode, timeout=180):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            deployment = self.request()
            # Um deploy concorrente ou remoção da anotação pelo GitOps não pode
            # ser apresentado como conclusão deste runbook.
            current_generation = deployment.get("metadata", {}).get("generation")
            annotations = deployment.get("spec", {}).get("template", {}).get("metadata", {}).get("annotations", {})
            if current_generation != generation or annotations.get(ANNOTATION) != episode:
                raise ValueError("rollout_superseded")
            status = deployment.get("status", {})
            desired = deployment.get("spec", {}).get("replicas", 1)
            if (desired > 0 and status.get("observedGeneration", 0) >= generation
                    and all(status.get(field, 0) == desired for field in
                            ("replicas", "updatedReplicas", "readyReplicas", "availableReplicas"))):
                return
            time.sleep(3)
        raise TimeoutError("rollout_timeout")


class Runbook:
    def __init__(self, ledger, kubernetes, now=time.time, launch=None):
        self.ledger, self.kubernetes, self.now = ledger, kubernetes, now
        self.launch = launch or self.launch_thread

    @staticmethod
    def launch_thread(function, episode):
        threading.Thread(target=function, args=(episode,), daemon=True).start()

    def accept(self, payload):
        if not isinstance(payload, dict) or not isinstance(payload.get("alerts"), list):
            raise ValueError("invalid_alerts")
        if len(payload["alerts"]) > 20:
            raise ValueError("too_many_alerts")
        candidates = []
        for alert in payload["alerts"]:
            if not isinstance(alert, dict):
                raise ValueError("invalid_alert")
            state = alert.get("status")
            if state not in ("firing", "resolved"):
                candidates.append(("ignored_not_firing", None))
                continue
            labels = alert.get("labels")
            expected = {"alertname": "AuthHigh5xx", "namespace": TARGET_NAMESPACE,
                        "service": TARGET_DEPLOYMENT}
            if not isinstance(labels, dict) or any(labels.get(k) != v for k, v in expected.items()):
                candidates.append(("ignored_target", None))
                continue
            starts_at = alert.get("startsAt", "")
            fingerprint = alert.get("fingerprint", "")
            if (not isinstance(starts_at, str) or not isinstance(fingerprint, str)
                    or not fingerprint or len(fingerprint) > 128):
                raise ValueError("invalid_episode")
            try:
                started = datetime.fromisoformat(starts_at.replace("Z", "+00:00"))
                if started.tzinfo is None:
                    raise ValueError("timestamp_requires_timezone")
                age = self.now() - started.timestamp()
            except (ValueError, OverflowError) as exc:
                raise ValueError("invalid_timestamp") from exc
            if age < -60 or age > 1800:
                candidates.append(("ignored_stale", None))
                continue
            canonical = started.astimezone(timezone.utc).isoformat()
            episode = hashlib.sha256((fingerprint + "|" + canonical).encode()).hexdigest()
            candidates.append((state, episode))

        # Valide o lote inteiro antes de qualquer efeito. Um HTTP 400 por um
        # segundo alerta malformado não deve esconder uma ação já disparada.
        results = []
        # Resoluções têm precedência dentro do mesmo lote, independentemente
        # da ordem enviada pelo emissor.
        for state, episode in candidates:
            if state == "resolved":
                self.ledger.resolve(episode)
        for state, episode in candidates:
            if state == "resolved":
                audit("webhook_decision", episode=episode, decision="resolved_recorded")
                results.append({"episode": episode, "status": "ignored_not_firing"})
                continue
            if state != "firing":
                results.append({"status": state})
                continue
            status = self.ledger.claim(episode)
            audit("webhook_decision", episode=episode, decision=status,
                  namespace=TARGET_NAMESPACE, deployment=TARGET_DEPLOYMENT)
            if status == "accepted":
                self.launch(self.execute, episode)
            results.append({"episode": episode, "status": status})
        return results

    def execute(self, episode):
        try:
            generation = self.kubernetes.restart(episode)
            self.ledger.record(episode, "restart_requested")
            audit("restart_requested", episode=episode, generation=generation,
                  namespace=TARGET_NAMESPACE, deployment=TARGET_DEPLOYMENT)
            self.kubernetes.wait_for_rollout(generation, episode)
            self.ledger.record(episode, "rollout_completed")
            # Rollout saudável não prova sozinho a recuperação funcional.
            audit("rollout_completed", episode=episode, functional_recovery="check_metrics_and_requests")
        except Exception as exc:
            self.ledger.record(episode, "failed")
            # Não imprimir body de HTTPError, tokens, headers nem payload do webhook.
            fields = {"episode": episode, "error_type": type(exc).__name__, "automatic_retry": False}
            if isinstance(exc, HTTPError):
                fields["http_status"] = exc.code
            audit("runbook_failed", **fields)


def handler_factory(runbook, token):
    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(10)

        def log_message(self, _format, *_args):
            return  # URLs/headers vindos do cliente não entram no log de acesso.

        def reply(self, status, body):
            data = json.dumps(body).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            self.reply(200 if self.path == "/health" else 404,
                       {"status": "ok"} if self.path == "/health" else {"error": "not_found"})

        def do_POST(self):
            if self.path != "/webhook":
                self.reply(404, {"error": "not_found"})
                return
            if not hmac.compare_digest(self.headers.get("Authorization", "").encode(), ("Bearer " + token).encode()):
                self.reply(401, {"error": "unauthorized"})
                return
            try:
                size = int(self.headers.get("Content-Length", "0"))
                if not 0 < size <= MAX_BODY:
                    self.reply(413, {"error": "invalid_size"})
                    return
                payload = json.loads(self.rfile.read(size))
                self.reply(202, {"actions": runbook.accept(payload)})
            except (ValueError, UnicodeDecodeError):
                self.reply(400, {"error": "invalid_payload"})
            except Exception as exc:
                audit("webhook_failed", error_type=type(exc).__name__)
                self.reply(503, {"error": "temporarily_unavailable"})
    return Handler


def main():
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    token = os.environ.get("RESPONDER_TOKEN", "")
    if len(token) < 32:
        raise SystemExit("RESPONDER_TOKEN deve ter pelo menos 32 caracteres")
    ledger = Ledger(os.environ.get("STATE_DB", "/data/actions.db"))
    runbook = Runbook(ledger, Kubernetes())
    server = ThreadingHTTPServer(("0.0.0.0", 8080), handler_factory(runbook, token))
    audit("runbook_ready", namespace=TARGET_NAMESPACE, deployment=TARGET_DEPLOYMENT)
    server.serve_forever()


if __name__ == "__main__":
    main()
