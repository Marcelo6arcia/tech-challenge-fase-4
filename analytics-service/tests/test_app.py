"""Testes do analytics-service."""

import json


def test_health_responde_ok(client):
    resposta = client.get("/health")

    assert resposta.status_code == 200
    assert resposta.get_json() == {"status": "ok"}


def test_worker_nao_e_iniciado_durante_os_testes(client):
    """Garante que o dublê de threading está no lugar — sem ele, a suíte
    ficaria consumindo a fila em background."""
    import threading
    from unittest.mock import MagicMock

    assert isinstance(threading.Thread, MagicMock)


def test_mensagem_valida_vira_item_no_dynamodb(dynamodb_client, sqs_client):
    import app as app_module

    corpo = {
        "user_id": "usuario-1",
        "flag_name": "nova-home",
        "result": True,
        "timestamp": "2026-01-01T00:00:00Z",
    }
    mensagem = {
        "MessageId": "msg-1",
        "ReceiptHandle": "recibo-1",
        "Body": json.dumps(corpo),
    }

    app_module.process_message(mensagem)

    dynamodb_client.put_item.assert_called_once()
    item = dynamodb_client.put_item.call_args.kwargs["Item"]

    assert item["user_id"]["S"] == "usuario-1"
    assert item["flag_name"]["S"] == "nova-home"
    assert item["result"]["BOOL"] is True
    assert item["event_id"]["S"]  # UUID gerado pelo serviço

    # Só depois de gravar é que a mensagem sai da fila
    sqs_client.delete_message.assert_called_once()


def test_mensagem_com_json_invalido_nao_e_removida_da_fila(dynamodb_client, sqs_client):
    """Uma poison pill não pode ser descartada silenciosamente."""
    import app as app_module

    mensagem = {
        "MessageId": "msg-2",
        "ReceiptHandle": "recibo-2",
        "Body": "isto não é json",
    }

    app_module.process_message(mensagem)

    dynamodb_client.put_item.assert_not_called()
    sqs_client.delete_message.assert_not_called()


def test_mensagem_sem_campo_obrigatorio_nao_e_removida_da_fila(dynamodb_client, sqs_client):
    import app as app_module

    mensagem = {
        "MessageId": "msg-3",
        "ReceiptHandle": "recibo-3",
        "Body": json.dumps({"user_id": "usuario-1"}),  # faltam flag_name, result, timestamp
    }

    app_module.process_message(mensagem)

    sqs_client.delete_message.assert_not_called()
