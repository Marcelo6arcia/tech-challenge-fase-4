#!/usr/bin/env python3
"""Prova local real: API → SQS → DynamoDB e três sinais de observabilidade.

Não sobe containers, não usa AWS real e não ativa a falha de demonstração.
"""

import argparse
import base64
import json
import re
import sys
import time
from pathlib import Path
from types import SimpleNamespace
from urllib.parse import urlencode

from demo import (ROOT, SERVICES, DemoError, Target, evaluate, http_json, json_output,
                  prepare, timestamp, write_json)


def otlp_id(value, length):
    """Accept OTLP JSON hexadecimal IDs and protobuf-JSON base64 IDs."""
    if not isinstance(value, str):
        return ""
    if re.fullmatch(rf"[0-9a-fA-F]{{{length * 2}}}", value):
        return value.lower()
    try:
        decoded = base64.b64decode(value, validate=True)
    except ValueError:
        return ""
    return decoded.hex() if len(decoded) == length else ""


def attribute_map(attributes):
    result = {}
    for attribute in attributes or []:
        value = attribute.get("value", {})
        for kind in ("stringValue", "intValue", "doubleValue", "boolValue", "string_value", "int_value"):
            if kind in value:
                result[attribute.get("key", "")] = value[kind]
                break
    return result


def otlp_records(path, signal):
    resource_key = "resourceSpans" if signal == "traces" else "resourceLogs"
    scope_key = "scopeSpans" if signal == "traces" else "scopeLogs"
    record_key = "spans" if signal == "traces" else "logRecords"
    if not path.is_file():
        return
    with path.open() as stream:
        for line in stream:
            try:
                document = json.loads(line)
            except json.JSONDecodeError:
                # The exporter may still be writing the final line. Retry later.
                continue
            for resource in document.get(resource_key, []):
                attributes = attribute_map(resource.get("resource", {}).get("attributes", []))
                service = attributes.get("service.name", "")
                for scope in resource.get(scope_key, []):
                    for record in scope.get(record_key, []):
                        yield service, record


def trace_evidence(path, trace_id):
    spans = {}
    for service, record in otlp_records(path, "traces"):
        if otlp_id(record.get("traceId"), 16) == trace_id:
            span_id = otlp_id(record.get("spanId"), 8)
            if span_id:
                spans[span_id] = {
                    "service": service, "parent": otlp_id(record.get("parentSpanId"), 8),
                    "kind": record.get("kind"), "name": record.get("name", ""),
                }
    roots = [span_id for span_id, span in spans.items()
             if span["service"] == "evaluation-service" and span["parent"] == ""
             and span["kind"] in (2, "SPAN_KIND_SERVER")]
    if len(roots) != 1:
        return None
    root = roots[0]

    def descendant(span_id):
        visited = set()
        while span_id and span_id not in visited:
            if span_id == root:
                return True
            visited.add(span_id)
            span_id = spans.get(span_id, {}).get("parent", "")
        return False

    linked = {span["service"] for span_id, span in spans.items() if descendant(span_id)}
    consumers = [span for span_id, span in spans.items() if span["service"] == "analytics-service"
                 and span["kind"] in (5, "SPAN_KIND_CONSUMER") and descendant(span_id)]
    if not set(SERVICES).issubset(linked) or not consumers:
        return None
    producer_linked = any(spans.get(span["parent"], {}).get("kind") in (4, "SPAN_KIND_PRODUCER") for span in consumers)
    if not producer_linked:
        return None
    return {"trace_id": trace_id, "services": sorted(linked), "span_count": len(spans),
            "evaluation_server_span_id": root, "evaluation_server_is_root": True,
            "analytics_consumer_parent_is_producer": True}


def file_log_evidence(path, trace_id):
    services = {service for service, record in otlp_records(path, "logs")
                if otlp_id(record.get("traceId"), 16) == trace_id and otlp_id(record.get("spanId"), 8)}
    return {"trace_id": trace_id, "services": sorted(services)} if set(SERVICES).issubset(services) else None


def wait_for(name, check, timeout):
    deadline = time.monotonic() + timeout
    while True:
        try:
            result = check()
        except DemoError:
            result = None
        if result:
            print(f"OK: {name}", flush=True)
            return result
        if time.monotonic() >= deadline:
            raise DemoError(f"Tempo limite aguardando {name} ({timeout}s).")
        time.sleep(2)


def dynamodb_evidence(env_file, state):
    result = json_output([
        "docker", "compose", "-p", "fiap4", "--env-file", str(env_file), "exec", "-T", "localstack",
        "awslocal", "dynamodb", "scan", "--table-name", "analytics-events", "--region", "us-east-1",
        "--consistent-read", "--filter-expression", "#flag = :flag AND #user = :user",
        "--expression-attribute-names", json.dumps({"#flag": "flag_name", "#user": "user_id"}),
        "--expression-attribute-values", json.dumps({":flag": {"S": state["flag_name"]},
                                                    ":user": {"S": state["user_id"]}}),
        "--output", "json",
    ], "consulta da tabela no LocalStack", timeout=15)
    matches = [item for item in result.get("Items", []) if item.get("result", {}).get("BOOL") is True]
    if not matches:
        return None
    return {"table": "analytics-events", "matching_events": len(matches), "result": True,
            "event_ids": [item.get("event_id", {}).get("S") for item in matches]}


def prometheus_evidence():
    query = "sum by (service_name) (app_http_requests_total)"
    status, data = http_json("http://127.0.0.1:19090/api/v1/query?" + urlencode({"query": query}))
    if status != 200 or data.get("status") != "success":
        return None
    counters = {item.get("metric", {}).get("service_name"): float(item["value"][1])
                for item in data.get("data", {}).get("result", [])}
    if not all(counters.get(service, 0) > 0 for service in SERVICES):
        return None
    query = 'sum(app_messages_processed_total{service_name="analytics-service"})'
    status, data = http_json("http://127.0.0.1:19090/api/v1/query?" + urlencode({"query": query}))
    values = data.get("data", {}).get("result", [])
    if status != 200 or not values or float(values[0]["value"][1]) <= 0:
        return None
    return {"http_requests": counters, "analytics_processed": float(values[0]["value"][1]),
            "note": "Contadores incluem /health; o dashboard separa tráfego de negócio."}


def loki_evidence(trace_id, started_ns):
    query = '{service_name=~"' + "|".join(SERVICES) + '"} | trace_id="' + trace_id + '"'
    status, data = http_json("http://127.0.0.1:13100/loki/api/v1/query_range?" + urlencode({
        "query": query, "start": str(started_ns), "end": str(time.time_ns()), "limit": "1000",
    }))
    if status != 200 or data.get("status") != "success":
        return None
    streams = data.get("data", {}).get("result", [])
    services = {stream.get("stream", {}).get("service_name") for stream in streams if stream.get("values")}
    if not set(SERVICES).issubset(services):
        return None
    return {"trace_id": trace_id, "services": sorted(services),
            "matching_lines": sum(len(stream.get("values", [])) for stream in streams)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env-file", type=Path, default=ROOT / ".env.local")
    parser.add_argument("--timeout", type=int, default=120, help="Tempo limite por etapa, entre 10 e 600 segundos")
    parser.add_argument("--report", type=Path, help="Relatório JSON; padrão .runs/local-smoke-<id>.json")
    args = parser.parse_args()
    if not 10 <= args.timeout <= 600:
        raise DemoError("--timeout deve estar entre 10 e 600 segundos.")
    target = Target(SimpleNamespace(mode="local", env_file=args.env_file, context=None,
                                    base_url=None, aws_account_id=None))
    started_ns = time.time_ns()
    report = {"started_at": timestamp(), "mode": "local", "checks": {}, "passed": False,
              "scope": "Stack Docker local; não comprova APM comercial, Kubernetes ou incidente externo."}
    report_path = args.report or ROOT / ".runs" / f"local-smoke-{started_ns}.json"
    try:
        def health():
            codes = {service: target.request(service, "/health")[0] for service in SERVICES}
            return codes if all(code == 200 for code in codes.values()) else None
        report["checks"]["health"] = wait_for("health dos cinco serviços", health, args.timeout)
        state = prepare(target)
        state = evaluate(target, state)
        report.update(run_id=state["run_id"], flag_name=state["flag_name"], user_id=state["user_id"],
                      trace_id=state["trace_id"], parent_span_id=state["parent_span_id"])
        report["checks"]["evaluation"] = {"http_status": 200, "result": True}
        report["checks"]["dynamodb"] = wait_for(
            "evento correspondente no DynamoDB local", lambda: dynamodb_evidence(target.env_file, state), args.timeout)
        report["checks"]["trace"] = wait_for(
            "trace ligado nos cinco serviços", lambda: trace_evidence(
                ROOT / ".runs/telemetry/traces.json", state["trace_id"]), args.timeout)
        report["checks"]["otlp_logs"] = wait_for(
            "logs OTLP correlacionados nos cinco serviços", lambda: file_log_evidence(
                ROOT / ".runs/telemetry/logs.json", state["trace_id"]), args.timeout)
        report["checks"]["prometheus"] = wait_for("métricas no Prometheus", prometheus_evidence, args.timeout)
        report["checks"]["loki"] = wait_for(
            "logs correlacionados no Loki", lambda: loki_evidence(state["trace_id"], started_ns), args.timeout)
        report["passed"] = True
    except DemoError as error:
        report["error"] = str(error)
    finally:
        report["finished_at"] = timestamp()
        write_json(report_path, report)
    print(json.dumps({"passed": report["passed"], "report": str(report_path.resolve()),
                      "trace_id": report.get("trace_id"), "checks_passed": sorted(report["checks"]),
                      "error": report.get("error")}, ensure_ascii=False, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except DemoError as error:
        print(f"Erro: {error}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("Interrompido pelo operador.", file=sys.stderr)
        sys.exit(130)
