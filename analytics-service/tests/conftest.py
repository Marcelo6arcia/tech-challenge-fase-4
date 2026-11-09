"""Configuração dos testes do analytics-service.

Dois cuidados aqui:
  1. O boto3 é substituído por um dublê — os testes não falam com a AWS.
  2. threading.Thread também é substituído: o app.py chama start_worker() no
     import, e sem isso o loop do SQS ficaria girando durante a suíte.
"""

import os
import sys
import threading
from pathlib import Path
from unittest.mock import MagicMock

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

# Unit tests must not start exporters or contact a Collector.
os.environ["OTEL_SDK_DISABLED"] = "true"

os.environ.setdefault("AWS_REGION", "us-east-1")
os.environ.setdefault("AWS_SQS_URL", "https://sqs.us-east-1.amazonaws.com/000000000000/fila-de-teste")
os.environ.setdefault("AWS_DYNAMODB_TABLE", "TabelaDeTeste")
os.environ.setdefault("AWS_ACCESS_KEY_ID", "testing")
os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "testing")

import boto3  # noqa: E402

_sqs_falso = MagicMock(name="sqs_client")
_sqs_falso.receive_message.return_value = {}

_dynamo_falso = MagicMock(name="dynamodb_client")

_sessao_falsa = MagicMock(name="Session")
_sessao_falsa.client.side_effect = lambda nome, *a, **kw: (
    _sqs_falso if nome == "sqs" else _dynamo_falso
)

boto3.Session = MagicMock(return_value=_sessao_falsa)
threading.Thread = MagicMock(name="Thread")

import app as app_module  # noqa: E402


@pytest.fixture
def client():
    app_module.app.config.update(TESTING=True)
    with app_module.app.test_client() as test_client:
        yield test_client


@pytest.fixture
def sqs_client():
    _sqs_falso.reset_mock()
    return _sqs_falso


@pytest.fixture
def dynamodb_client():
    _dynamo_falso.reset_mock()
    return _dynamo_falso
