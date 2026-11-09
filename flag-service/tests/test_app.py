"""Testes do flag-service."""

from unittest.mock import MagicMock, patch


def test_health_responde_ok(client):
    """O /health é usado pelas probes do Kubernetes: precisa responder 200 sempre."""
    resposta = client.get("/health")

    assert resposta.status_code == 200
    assert resposta.get_json() == {"status": "ok"}


def test_health_nao_exige_autenticacao(client):
    """Se o /health exigisse chave, as probes derrubariam o pod em loop."""
    resposta = client.get("/health")

    assert resposta.status_code != 401


def test_endpoint_protegido_sem_authorization_retorna_401(client):
    resposta = client.get("/flags")

    assert resposta.status_code == 401
    assert "error" in resposta.get_json()


def test_endpoint_protegido_com_chave_invalida_retorna_401(client):
    falha = MagicMock(status_code=401)

    with patch("app.requests.get", return_value=falha):
        resposta = client.get("/flags", headers={"Authorization": "Bearer chave-invalida"})

    assert resposta.status_code == 401


def test_auth_service_indisponivel_retorna_503(client):
    """Falha do auth-service não pode virar 500: o cliente precisa saber que é temporário."""
    import requests

    with patch("app.requests.get", side_effect=requests.exceptions.ConnectionError()):
        resposta = client.get("/flags", headers={"Authorization": "Bearer tm_key_x"})

    assert resposta.status_code == 503


def test_auth_service_em_timeout_retorna_504(client):
    import requests

    with patch("app.requests.get", side_effect=requests.exceptions.Timeout()):
        resposta = client.get("/flags", headers={"Authorization": "Bearer tm_key_x"})

    assert resposta.status_code == 504


def test_criar_flag_sem_nome_retorna_400(client):
    ok = MagicMock(status_code=200)

    with patch("app.requests.get", return_value=ok):
        resposta = client.post(
            "/flags",
            headers={"Authorization": "Bearer tm_key_x"},
            json={"description": "sem o campo name"},
        )

    assert resposta.status_code == 400


def test_rota_inexistente_retorna_404(client):
    assert client.get("/rota-que-nao-existe").status_code == 404
