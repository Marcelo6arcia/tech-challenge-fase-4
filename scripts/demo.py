#!/usr/bin/env python3
"""Comandos acadêmicos de demonstração. Nunca imprime credenciais ou reinicia pods."""

import argparse
import base64
import json
import os
import re
import secrets
import subprocess
import sys
import time
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener

ROOT = Path(__file__).resolve().parents[1]
SERVICES = ("auth-service", "flag-service", "targeting-service", "evaluation-service", "analytics-service")
PREFIXES = dict(zip(SERVICES, ("auth", "flag", "targeting", "evaluation", "analytics")))
CONTEXT = "togglemaster-fase4"


class DemoError(RuntimeError):
    """Safe, operator-facing error; never include response bodies or credentials."""


def timestamp():
    return datetime.now(timezone.utc).isoformat()


def read_env(path):
    """Parse the generated dotenv as data, without shell evaluation/interpolation."""
    values = {}
    try:
        lines = Path(path).read_text().splitlines()
    except OSError:
        raise DemoError("Arquivo .env.local indisponível; execute scripts/local-env.py.") from None
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        key, separator, value = line.partition("=")
        if not separator or not re.fullmatch(r"[A-Z][A-Z0-9_]*", key):
            raise DemoError("Formato inválido no arquivo de ambiente local.")
        if value[:1] in {"'", '"'} and value[-1:] == value[:1]:
            value = value[1:-1]
        values[key] = value
    return values


def checked_output(command, operation, *, env=None, timeout=30):
    try:
        result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired):
        raise DemoError(f"Falha em {operation}; verifique ferramentas, acesso e tempo limite.") from None
    if result.returncode:
        raise DemoError(f"Falha em {operation}; saída omitida para proteger credenciais.")
    return result.stdout


def json_output(command, operation, **kwargs):
    try:
        return json.loads(checked_output(command, operation, **kwargs))
    except json.JSONDecodeError:
        raise DemoError(f"Resposta JSON inválida em {operation}.") from None


def validate_base_url(value):
    parsed = urlsplit(value)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise DemoError("--base-url precisa ser uma URL HTTP(S) explícita do Ingress acadêmico.")
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise DemoError("--base-url não pode conter credenciais, query string ou fragmento.")
    if parsed.scheme != "https" and parsed.hostname not in {"127.0.0.1", "localhost", "::1"}:
        raise DemoError("--base-url exige HTTPS; HTTP é permitido somente no loopback via port-forward acadêmico.")
    return value.rstrip("/")


class NoRedirect(HTTPRedirectHandler):
    """Never forward an Authorization header or request body through redirects."""

    def redirect_request(self, request, response, code, message, headers, new_url):
        return None


def http_json(url, *, method="GET", key=None, body=None, traceparent=None, timeout=8, return_trace_id=False):
    """Return status/body; optionally append only the response correlation ID."""
    headers = {"Accept": "application/json"}
    if key:
        headers["Authorization"] = "Bearer " + key
    if traceparent:
        headers["traceparent"] = traceparent
    data = None if body is None else json.dumps(body).encode()
    if data is not None:
        headers["Content-Type"] = "application/json"
    request = Request(url, data=data, headers=headers, method=method)
    response_trace_id = ""
    try:
        # Never forward credentials through a proxy selected by ambient env vars.
        with build_opener(ProxyHandler({}), NoRedirect()).open(request, timeout=timeout) as response:
            status, payload = response.status, response.read(1024 * 1024)
            if return_trace_id:
                response_trace_id = response.headers.get("X-Trace-Id", "")
    except HTTPError as error:
        status, payload = error.code, error.read(1024 * 1024)
        if return_trace_id and error.headers is not None:
            response_trace_id = error.headers.get("X-Trace-Id", "")
    except (URLError, TimeoutError, OSError):
        return (0, {}, "") if return_trace_id else (0, {})
    try:
        decoded = json.loads(payload)
    except (json.JSONDecodeError, UnicodeDecodeError):
        decoded = {}
    result = (status, decoded if isinstance(decoded, dict) else {})
    return result + (response_trace_id,) if return_trace_id else result


def write_json(path, payload):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w") as stream:
        json.dump(payload, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    os.replace(temporary, path)


class Target:
    def __init__(self, args):
        self.mode = args.mode
        self.identity = "local"
        self.context = args.context
        self.env_file = Path(args.env_file).resolve()
        self.state_file = ROOT / ".runs" / f"demo-{self.mode}.json"
        self._keys = {}
        if self.mode == "local":
            if args.base_url or args.context or args.aws_account_id:
                raise DemoError("Modo local usa somente 127.0.0.1:18001..18005; remova opções de cluster.")
            self.urls = {service: f"http://127.0.0.1:{18001 + index}" for index, service in enumerate(SERVICES)}
        else:
            if args.context != CONTEXT:
                raise DemoError(f"Modo cluster exige --context {CONTEXT} explícito.")
            if not args.base_url or not re.fullmatch(r"[0-9]{12}", args.aws_account_id or ""):
                raise DemoError("Modo cluster exige --base-url e --aws-account-id com a conta FIAP esperada.")
            base = validate_base_url(args.base_url)
            self.identity = f"{args.aws_account_id}:{CONTEXT}:{base}"
            self.aws_env = {**os.environ, "AWS_PROFILE": "fiap", "AWS_DEFAULT_PROFILE": "fiap", "AWS_PAGER": ""}
            # Prevent ambient static credentials from overriding the academic profile.
            for variable in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN", "AWS_SECURITY_TOKEN"):
                self.aws_env.pop(variable, None)
            # STS runs first, before even the read-only kubectl config call.
            caller = json_output(
                ["aws", "--profile", "fiap", "sts", "get-caller-identity", "--output", "json"],
                "validação da conta AWS FIAP", env=self.aws_env,
            )
            if caller.get("Account") != args.aws_account_id:
                raise DemoError("A identidade do profile fiap não corresponde à conta esperada. Operação interrompida.")
            config = json_output(
                ["kubectl", "--context", CONTEXT, "config", "view", "--minify", "-o", "json"],
                "validação do kubeconfig", env=self.aws_env,
            )
            self._validate_kubeconfig(config, args.aws_account_id)
            self.urls = {service: base + "/" + PREFIXES[service] for service in SERVICES}

    @staticmethod
    def _validate_kubeconfig(config, account):
        contexts = config.get("contexts", [])
        if len(contexts) != 1 or contexts[0].get("name") != CONTEXT:
            raise DemoError("O kubeconfig não contém o contexto acadêmico esperado.")
        cluster = contexts[0].get("context", {}).get("cluster", "")
        if not re.fullmatch(rf"arn:aws:eks:[a-z0-9-]+:{account}:cluster/[A-Za-z0-9_-]+", cluster):
            raise DemoError("O contexto deve referenciar um ARN EKS da conta FIAP esperada.")
        users = config.get("users", [])
        if len(users) != 1:
            raise DemoError("O kubeconfig deve identificar exatamente um usuário AWS CLI.")
        cluster_name = cluster.split("/", 1)[1]
        for user in users:
            execution = user.get("user", {}).get("exec", {})
            if Path(execution.get("command", "")).name != "aws":
                raise DemoError("O contexto deve usar o autenticador AWS CLI do profile fiap.")
            arguments = execution.get("args", [])
            if "eks" not in arguments or "get-token" not in arguments:
                raise DemoError("O autenticador deve executar aws eks get-token.")
            if "--cluster-name" not in arguments:
                raise DemoError("O autenticador precisa informar o nome do cluster EKS.")
            cluster_index = arguments.index("--cluster-name")
            if arguments[cluster_index + 1:cluster_index + 2] != [cluster_name]:
                raise DemoError("O autenticador aponta para outro cluster EKS.")
            for role_flag in ("--role-arn", "--assume-role-arn"):
                if role_flag in arguments:
                    index = arguments.index(role_flag)
                    role = arguments[index + 1:index + 2]
                    if not role or not role[0].startswith(f"arn:aws:iam::{account}:role/"):
                        raise DemoError("O autenticador aponta para uma role de outra conta.")
            if "--profile" in arguments:
                index = arguments.index("--profile")
                if arguments[index + 1:index + 2] != ["fiap"]:
                    raise DemoError("O kubeconfig seleciona outro profile AWS.")
            if any(arg.startswith("--profile=") and arg != "--profile=fiap" for arg in arguments):
                raise DemoError("O kubeconfig seleciona outro profile AWS.")
            for item in execution.get("env", []):
                if item.get("name") in {"AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN"}:
                    raise DemoError("O autenticador não pode substituir o profile por credenciais inline.")
                if item.get("name") in {"AWS_PROFILE", "AWS_DEFAULT_PROFILE"} and item.get("value") != "fiap":
                    raise DemoError("O kubeconfig contém um profile diferente de fiap.")

    def kubectl(self, arguments):
        return json_output(
            ["kubectl", "--context", CONTEXT, "--namespace", "togglemaster", *arguments],
            "consulta Kubernetes acadêmica", env=self.aws_env,
        )

    def key(self, name):
        if name not in {"SERVICE_API_KEY", "MASTER_KEY"}:
            raise DemoError("Nome de credencial não permitido.")
        if name not in self._keys:
            if self.mode == "local":
                self._keys[name] = read_env(self.env_file).get(name, "")
            else:
                secret = "auth-service-secret" if name == "MASTER_KEY" else "evaluation-service-secret"
                # Only the requested key is returned, never a complete Secret.
                value = checked_output(
                    ["kubectl", "--context", CONTEXT, "--namespace", "togglemaster", "get", "secret", secret,
                     "-o", "jsonpath={.data." + name + "}"],
                    "leitura da chave acadêmica necessária", env=self.aws_env,
                )
                try:
                    self._keys[name] = base64.b64decode(value, validate=True).decode()
                except (ValueError, UnicodeDecodeError):
                    raise DemoError("Secret acadêmico não contém uma chave válida.") from None
            if not self._keys[name] or "\n" in self._keys[name] or "\r" in self._keys[name]:
                raise DemoError("Credencial acadêmica ausente ou inválida.")
        return self._keys[name]

    def request(self, service, path, **kwargs):
        return http_json(self.urls[service] + path, **kwargs)


def prepare(target):
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S") + "-" + secrets.token_hex(4)
    flag = "fiap4-" + run_id
    key = target.key("SERVICE_API_KEY")
    status, _ = target.request("flag-service", "/flags", method="POST", key=key, body={
        "name": flag, "description": "Demonstração acadêmica fase 4", "is_enabled": True,
    })
    if status != 201:
        raise DemoError(f"Não foi possível criar a flag de demonstração (HTTP {status}).")
    status, _ = target.request("targeting-service", "/rules", method="POST", key=key, body={
        "flag_name": flag, "is_enabled": True, "rules": {"type": "PERCENTAGE", "value": 100},
    })
    if status != 201:
        raise DemoError(f"Flag criada, mas a regra não foi criada (HTTP {status}); execute prepare novamente.")
    state = {"run_id": run_id, "flag_name": flag, "user_id": "fiap4-demo-" + secrets.token_hex(4),
             "target": target.identity, "prepared_at": timestamp(), "evaluated": False}
    write_json(target.state_file, state)
    return state


def evaluate(target, state):
    query = urlencode({"user_id": state["user_id"], "flag_name": state["flag_name"]})
    status, result, trace_id = target.request(
        "evaluation-service", "/evaluate?" + query, return_trace_id=True,
    )
    if status != 200 or result.get("result") is not True or result.get("flag_name") != state["flag_name"]:
        raise DemoError(f"A avaliação não retornou o resultado true esperado (HTTP {status}).")
    if not re.fullmatch(r"[0-9a-fA-F]{32}", trace_id) or int(trace_id, 16) == 0:
        raise DemoError("A avaliação não devolveu um X-Trace-Id válido; confira a instrumentação do evaluation-service.")
    state.update(evaluated=True, trace_id=trace_id.lower(), parent_span_id="", evaluated_at=timestamp())
    write_json(target.state_file, state)
    return state


def trace_request(target):
    try:
        state = json.loads(target.state_file.read_text())
    except (OSError, json.JSONDecodeError):
        state = {}
    # A new flag avoids the 30s cache; changing only user_id would not suffice.
    if state.get("target") != target.identity or state.get("evaluated") is not False:
        state = prepare(target)
    return evaluate(target, state)


def load(target, seconds, rate):
    key = target.key("SERVICE_API_KEY")
    counts = Counter()
    started = time.monotonic()
    deadline, next_request, next_progress = started + seconds, started, started + 10
    interrupted = False
    try:
        while time.monotonic() < deadline:
            status, _ = target.request("auth-service", "/validate", key=key, timeout=min(5, seconds))
            counts[str(status or "connection_error")] += 1
            next_request += 1 / rate
            now = time.monotonic()
            if now >= next_progress:
                print(json.dumps({"event": "load_progress", "elapsed_seconds": round(now - started),
                                  "requests": sum(counts.values()), "statuses": dict(counts)}), flush=True)
                next_progress = now + 10
            time.sleep(max(0, min(next_request - time.monotonic(), deadline - time.monotonic())))
    except KeyboardInterrupt:
        interrupted = True
    return {"command": "load", "duration_seconds": round(time.monotonic() - started, 2),
            "requested_rps": rate, "requests": sum(counts.values()), "statuses": dict(counts),
            "interrupted": interrupted}


def status(target):
    health = {service: target.request(service, "/health")[0] for service in SERVICES}
    counts = Counter()
    for _ in range(10):
        code, _ = target.request("auth-service", "/validate", key=target.key("SERVICE_API_KEY"))
        counts[str(code or "connection_error")] += 1
    result = {"command": "status", "health_http": health, "auth_validate_samples": dict(counts),
              "note": "Health 200 não prova ausência de falha; observe /validate e o alerta."}
    if target.mode == "cluster":
        pods = target.kubectl(["get", "pods", "-l", "app.kubernetes.io/name=auth-service", "-o", "json"])
        result["auth_pods"] = [{"name": item["metadata"]["name"], "phase": item.get("status", {}).get("phase"),
                                "created_at": item["metadata"].get("creationTimestamp")}
                               for item in pods.get("items", [])]
    return result


def parser():
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("command", choices=("prepare", "trace", "load", "fault", "status"))
    value.add_argument("--mode", choices=("local", "cluster"), default="local")
    value.add_argument("--env-file", default=str(ROOT / ".env.local"))
    value.add_argument("--base-url", help="HTTPS do Ingress ou HTTP de loopback via port-forward (cluster apenas)")
    value.add_argument("--context", help=f"Obrigatório no cluster: {CONTEXT}")
    value.add_argument("--aws-account-id", help="ID de 12 dígitos da conta FIAP esperada")
    value.add_argument("--seconds", type=int, default=180, help="Carga: 1 a 600 segundos")
    value.add_argument("--rps", type=float, default=5, help="Carga sequencial: mais de 0 até 20 req/s")
    return value


def main():
    args = parser().parse_args()
    if not 1 <= args.seconds <= 600 or not 0 < args.rps <= 20:
        raise DemoError("Carga limitada a 1..600 segundos e (0,20] requisições/s.")
    target = Target(args)
    if args.command == "prepare":
        result = {"command": "prepare", **prepare(target)}
    elif args.command == "trace":
        result = {"command": "trace", **trace_request(target),
                  "note": "Busque este trace_id no APM e confirme os cinco serviços, inclusive analytics."}
    elif args.command == "load":
        result = load(target, args.seconds, args.rps)
    elif args.command == "status":
        result = status(target)
    else:
        code, body = target.request("auth-service", "/admin/demo/fault", method="POST", key=target.key("MASTER_KEY"))
        if code != 200 or body.get("fault_active") is not True:
            raise DemoError(f"Falha não ativada (HTTP {code}); confira DEMO_FAULT_ENABLED e a chave acadêmica.")
        result = {"command": "fault", "fault_active": True,
                  "note": "Falha em memória ativada. Aguarde o alerta e a automação; este script não reinicia pods."}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 130 if result.get("interrupted") else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except DemoError as error:
        print(f"Erro: {error}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("Interrompido pelo operador.", file=sys.stderr)
        sys.exit(130)
