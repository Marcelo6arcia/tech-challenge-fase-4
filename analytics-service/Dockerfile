# =============================================================================
# Multi-stage build — analytics-service (Flask + worker SQS em thread)
# =============================================================================
FROM python:3.12-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# Atualização direcionada: corrige perl-base sem executar um upgrade geral.
RUN apt-get update \
 && apt-get install -y --no-install-recommends --only-upgrade perl-base \
 && dpkg --compare-versions "$(dpkg-query -W -f='${Version}' perl-base)" ge 5.40.1-6+deb13u1 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

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

# Atualização direcionada: corrige perl-base sem executar um upgrade geral.
RUN apt-get update \
 && apt-get install -y --no-install-recommends --only-upgrade perl-base \
 && dpkg --compare-versions "$(dpkg-query -W -f='${Version}' perl-base)" ge 5.40.1-6+deb13u1 \
 && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 10001 app \
 && useradd --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY --chown=app:app . .

USER 10001

EXPOSE 8080

# --workers 1 é obrigatório: o worker SQS roda em thread de background por
# processo. Manter 1 preserva um único consumidor por réplica; SQS ainda pode
# redeliver mensagens, pois a entrega é pelo menos uma vez.
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "1", "--timeout", "120", "--access-logfile", "-", "app:app"]
