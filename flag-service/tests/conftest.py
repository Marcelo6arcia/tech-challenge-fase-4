"""Configuração dos testes do flag-service.

O app.py cria o pool de conexões e valida as variáveis de ambiente já no import
do módulo. Por isso as variáveis e os dublês de teste precisam existir ANTES do
`import app` — que é exatamente o que este conftest faz, já que o pytest carrega
o conftest antes dos arquivos de teste.
"""

import os
import sys
from pathlib import Path
from unittest.mock import MagicMock

import pytest

# Permite `import app` a partir da raiz do serviço
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

# Unit tests must not start exporters or contact a Collector.
os.environ["OTEL_SDK_DISABLED"] = "true"

os.environ.setdefault("DATABASE_URL", "postgresql://test:test@localhost:5432/testdb")
os.environ.setdefault("AUTH_SERVICE_URL", "http://auth-service:8080")

# Substitui o pool real por um dublê antes de o app.py ser importado
import psycopg2.pool  # noqa: E402

psycopg2.pool.SimpleConnectionPool = MagicMock(name="SimpleConnectionPool")

import app as app_module  # noqa: E402


@pytest.fixture
def client():
    """Cliente de teste do Flask."""
    app_module.app.config.update(TESTING=True)
    with app_module.app.test_client() as test_client:
        yield test_client


@pytest.fixture
def flask_app():
    return app_module.app
