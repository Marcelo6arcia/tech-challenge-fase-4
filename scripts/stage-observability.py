#!/usr/bin/env python3
"""Prepara os dois JSONs de integração no disco local, sem acessar a AWS."""

import getpass
import json
import os
from pathlib import Path
import re
import secrets
import sys
import warnings


ROOT = Path(__file__).resolve().parents[1]
JSM_URL = "https://api.atlassian.com/jsm/ops/integration/v2/alerts"
UUID = r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}"
JIRA_URL = rf"https://api-private\.atlassian\.com/automation/webhooks/jira/a/{UUID}/{UUID}"
DISCORD_URL = r"https://discord\.com/api/(?:v[0-9]+/)?webhooks/[0-9]{17,22}/[A-Za-z0-9_-]{30,200}"
TOKEN = r"[A-Za-z0-9_.~+/=\-]{16,300}"


def read_value(label, pattern):
    while True:
        value = getpass.getpass(f"{label} (oculto): ").strip()
        if re.fullmatch(pattern, value):
            return value
        print("Formato inválido para esse campo. Confira o valor e tente novamente.", file=sys.stderr)


def main():
    if not sys.stdin.isatty() or not sys.stderr.isatty():
        print("Execute em um Terminal interativo.", file=sys.stderr)
        return 1

    runs = ROOT / ".runs"
    destination = runs / "eks-observability"
    if runs.is_symlink() or destination.exists() or destination.is_symlink():
        print("Já existe uma área de staging. Revise-a antes de repetir.", file=sys.stderr)
        return 1

    with warnings.catch_warnings():
        warnings.simplefilter("error", getpass.GetPassWarning)
        incidents = {
            "DISCORD_WEBHOOK_URL": read_value("Webhook Discord acadêmico", DISCORD_URL),
            "JSM_OPERATIONS_API_URL": JSM_URL,
            "JSM_OPERATIONS_API_KEY": read_value("API key da integração JSM", TOKEN),
            "JIRA_AUTOMATION_WEBHOOK_URL": read_value("Webhook URL da regra FIAP4", JIRA_URL),
            "JIRA_AUTOMATION_WEBHOOK_TOKEN": read_value("Secret da regra FIAP4", TOKEN),
            "RESPONDER_TOKEN": secrets.token_urlsafe(32),
        }
        apm = {"NEW_RELIC_LICENSE_KEY": read_value("License key da conta acadêmica New Relic", TOKEN)}

    runs.mkdir(mode=0o700, exist_ok=True)
    destination.mkdir(mode=0o700)
    created = []
    try:
        for name, data in (("incidents.json", incidents), ("apm.json", apm)):
            path = destination / name
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            created.append(path)
            with os.fdopen(fd, "w") as stream:
                json.dump(data, stream)
                stream.write("\n")
    except (OSError, KeyboardInterrupt):
        for path in created:
            path.unlink(missing_ok=True)
        destination.rmdir()
        raise

    print("Staging privado do EKS pronto. Nenhum destino foi contatado.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (EOFError, getpass.GetPassWarning, KeyboardInterrupt, OSError):
        print("\nStaging cancelado. Nenhum valor foi enviado.", file=sys.stderr)
        raise SystemExit(1) from None
