#!/usr/bin/env python3
"""Gera segredos exclusivos da stack local sem imprimi-los nem sobrescrevê-los."""
import hashlib
import os
import secrets
from pathlib import Path

root = Path(__file__).resolve().parents[1]
target = root / ".env.local"
if target.exists():
    print(".env.local já existe; valores preservados.")
else:
    service_key = "tm_key_" + secrets.token_hex(32)
    values = {
        "LOCAL_DB_PASSWORD": secrets.token_hex(24),
        "MASTER_KEY": secrets.token_hex(32),
        "SERVICE_API_KEY": service_key,
        "SERVICE_API_KEY_HASH": hashlib.sha256(service_key.encode()).hexdigest(),
    }
    descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w") as stream:
        stream.write("\n".join(f"{name}={value}" for name, value in values.items()) + "\n")
    print(".env.local criado com valores aleatórios exclusivos dos testes locais.")
(root / ".runs" / "telemetry").mkdir(parents=True, exist_ok=True)
