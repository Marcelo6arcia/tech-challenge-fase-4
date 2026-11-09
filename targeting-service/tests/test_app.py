"""Testes do targeting-service."""

from unittest.mock import MagicMock, patch


def test_health_responde_ok(client):
    resposta = client.get("/health")

    assert resposta.status_code == 200
    assert resposta.get_json() == {"status": "ok"}


def test_health_nao_exige_autenticacao(client):
    assert client.get("/health").status_code != 401


def test_regras_sem_authorization_retorna_401(client):
    resposta = client.get("/rules/minha-flag")

    assert resposta.status_code == 401


def test_regras_com_chave_invalida_retorna_401(client):
    falha = MagicMock(status_code=401)

    with patch("app.requests.get", return_value=falha):
        resposta = client.get("/rules/minha-flag", headers={"Authorization": "Bearer invalida"})

    assert resposta.status_code == 401


def test_auth_service_indisponivel_retorna_503(client):
    import requests

    with patch("app.requests.get", side_effect=requests.exceptions.ConnectionError()):
        resposta = client.get("/rules/minha-flag", headers={"Authorization": "Bearer tm_key_x"})

    assert resposta.status_code == 503


def test_auth_service_em_timeout_retorna_504(client):
    import requests

    with patch("app.requests.get", side_effect=requests.exceptions.Timeout()):
        resposta = client.get("/rules/minha-flag", headers={"Authorization": "Bearer tm_key_x"})

    assert resposta.status_code == 504


def test_criar_regra_com_corpo_vazio_retorna_400(client):
    ok = MagicMock(status_code=200)

    with patch("app.requests.get", return_value=ok):
        resposta = client.post(
            "/rules",
            headers={"Authorization": "Bearer tm_key_x"},
            json={},
        )

    assert resposta.status_code == 400


def test_rota_inexistente_retorna_404(client):
    assert client.get("/nao-existe").status_code == 404
