FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
# Atualização direcionada: corrige perl-base sem executar um upgrade geral.
RUN apt-get update \
 && apt-get install -y --no-install-recommends --only-upgrade perl-base \
 && dpkg --compare-versions "$(dpkg-query -W -f='${Version}' perl-base)" ge 5.40.1-6+deb13u1 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN groupadd --gid 10001 app && useradd --uid 10001 --gid app --no-create-home app
COPY --chown=10001:10001 responder.py /app/responder.py
USER 10001:10001
EXPOSE 8080
CMD ["python", "/app/responder.py"]
