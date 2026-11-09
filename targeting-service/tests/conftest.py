"""Configuração dos testes do targeting-service.

Mesma estratégia do flag-service: as variáveis de ambiente e o dublê do pool de
conexões precisam existir antes do `import app`, porque o módulo se conecta ao
banco já no import.
"""

import os
import sys
from pathlib import Path
from unittest.mock import MagicMock

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

# Unit tests must not start exporters or contact a Collector.
os.environ["OTEL_SDK_DISABLED"] = "true"

os.environ.setdefault("DATABASE_URL", "postgresql://test:test@localhost:5432/testdb")
os.environ.setdefault("AUTH_SERVICE_URL", "http://auth-service:8080")

import psycopg2.pool  # noqa: E402

psycopg2.pool.SimpleConnectionPool = MagicMock(name="SimpleConnectionPool")

import app as app_module  # noqa: E402


@pytest.fixture
def client():
    app_module.app.config.update(TESTING=True)
    with app_module.app.test_client() as test_client:
        yield test_client
