"""Impede novas operações fora da janela autorizada; não faz teardown."""

import datetime
import os


def validate_expiry(value, now):
    try:
        expiry = datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (ValueError, AttributeError) as exc:
        raise ValueError("Defina CLOUD_EXPIRES_AT com data/hora UTC da janela autorizada.") from exc
    if expiry.tzinfo is None:
        raise ValueError("A expiração precisa conter fuso horário.")
    remaining = expiry - now
    if not datetime.timedelta(0) < remaining <= datetime.timedelta(hours=72):
        raise ValueError("Janela ausente, expirada ou superior às 72 horas autorizadas.")


if __name__ == "__main__":
    validate_expiry(os.environ.get("CLOUD_EXPIRES_AT", ""), datetime.datetime.now(datetime.timezone.utc))
    print("Dentro da janela autorizada. O encerramento de recursos é uma etapa separada.")
