# =============================================================================
# Multi-stage build — serviço Python (Flask + gunicorn)
# =============================================================================
# Endurecimentos aplicados na Fase 3:
#   - base python:3.12-slim (a 3.11 acumulava CVEs de sistema no scan do Trivy)
#   - dependências instaladas em venv próprio, copiado para a imagem final
#   - processo roda como usuário sem privilégio (UID 10001)
#   - PYTHONDONTWRITEBYTECODE / PYTHONUNBUFFERED para imagem menor e log direto
# =============================================================================

FROM python:3.12-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# perl-base >= 5.40.1-6+deb13u1 corrige as três CVEs CRITICAL detectadas no gate.
# gcc só existe no estágio de build; não vai para a imagem final
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential libpq-dev perl-base \
 && dpkg --compare-versions "$(dpkg-query -W -f='${Version}' perl-base)" ge 5.40.1-6+deb13u1 \
 && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install --upgrade pip setuptools wheel \
 && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

# -----------------------------------------------------------------------------
FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    PORT=8080

RUN apt-get update \
 && apt-get install -y --no-install-recommends libpq5 perl-base \
 && dpkg --compare-versions "$(dpkg-query -W -f='${Version}' perl-base)" ge 5.40.1-6+deb13u1 \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --gid 10001 app \
 && useradd --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY --chown=app:app . .

USER 10001

EXPOSE 8080

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--access-logfile", "-", "app:app"]
