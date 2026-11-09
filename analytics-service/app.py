import json
import logging
import os
import sys
import threading
import time
import uuid

import boto3
from botocore.exceptions import ClientError, NoCredentialsError
from dotenv import load_dotenv
from flask import Flask, jsonify
from opentelemetry.context import Context
from opentelemetry.trace import SpanKind, Status, StatusCode
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator

from telemetry import configure_telemetry

# Configura o logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
log = logging.getLogger(__name__)

# Carrega .env para desenvolvimento local
load_dotenv()

telemetry = configure_telemetry("analytics-service")

# --- Configuração ---
AWS_REGION = os.getenv("AWS_REGION")
SQS_QUEUE_URL = os.getenv("AWS_SQS_URL")
DYNAMODB_TABLE_NAME = os.getenv("AWS_DYNAMODB_TABLE")
QUEUE_NAME = (SQS_QUEUE_URL or "").rstrip("/").rsplit("/", 1)[-1]
messages_processed = telemetry.meter.create_counter("app.messages.processed", unit="{message}")
messages_errors = telemetry.meter.create_counter("app.messages.errors", unit="{message}")

if not all([AWS_REGION, SQS_QUEUE_URL, DYNAMODB_TABLE_NAME]):
    log.critical("Erro: AWS_REGION, AWS_SQS_URL, e AWS_DYNAMODB_TABLE devem ser definidos.")
    sys.exit(1)

# --- Clientes Boto3 ---
# Criamos a sessão uma vez
try:
    session = boto3.Session(region_name=AWS_REGION)
    sqs_client = session.client("sqs")
    dynamodb_client = session.client("dynamodb")
    log.info(f"Clientes Boto3 inicializados na região {AWS_REGION}")
except NoCredentialsError:
    log.critical("Credenciais da AWS não encontradas. Verifique seu ambiente.")
    sys.exit(1)
except Exception as e:
    log.critical(f"Erro ao inicializar o Boto3: {e}")
    sys.exit(1)


# --- SQS Worker ---

def message_context(message):
    """Extract only W3C tracing fields; a message cannot inherit the previous one."""
    attributes = message.get("MessageAttributes", {})
    carrier = {
        name: attributes[name]["StringValue"]
        for name in ("traceparent", "tracestate")
        if isinstance(attributes.get(name), dict)
        and isinstance(attributes[name].get("StringValue"), str)
    }
    return TraceContextTextMapPropagator().extract(carrier, context=Context())


def persist_message(message):
    """Persist before acknowledging, preserving the original at-least-once behavior."""
    body = json.loads(message["Body"])
    event_id = str(uuid.uuid4())
    item = {
        "event_id": {"S": event_id},
        "user_id": {"S": body["user_id"]},
        "flag_name": {"S": body["flag_name"]},
        "result": {"BOOL": body["result"]},
        "timestamp": {"S": body["timestamp"]},
    }
    with telemetry.tracer.start_as_current_span(
        "DynamoDB PutItem", kind=SpanKind.CLIENT,
        attributes={
            "db.system.name": "aws.dynamodb",
            "db.system": "dynamodb",
            "db.operation.name": "PutItem",
            "db.collection.name": DYNAMODB_TABLE_NAME,
            "aws.region": AWS_REGION,
        },
    ):
        dynamodb_client.put_item(TableName=DYNAMODB_TABLE_NAME, Item=item)
    log.info("Event persisted in DynamoDB", extra={"event.id": event_id})
    with telemetry.tracer.start_as_current_span(
        f"{QUEUE_NAME} acknowledge", kind=SpanKind.CLIENT,
        attributes={
            "messaging.system": "aws_sqs",
            "messaging.destination.name": QUEUE_NAME,
            "messaging.operation.name": "delete",
            "messaging.operation.type": "settle",
        },
    ):
        sqs_client.delete_message(QueueUrl=SQS_QUEUE_URL, ReceiptHandle=message["ReceiptHandle"])


def process_message(message):
    """Continue the producer trace while processing one SQS message."""
    attributes = {
        "messaging.system": "aws_sqs",
        "messaging.destination.name": QUEUE_NAME,
        "messaging.operation.name": "process",
        "messaging.operation.type": "process",
        "messaging.message.id": message.get("MessageId", "unknown"),
    }
    with telemetry.tracer.start_as_current_span(
        f"{QUEUE_NAME} process", context=message_context(message),
        kind=SpanKind.CONSUMER, attributes=attributes,
    ) as span:
        metric_attributes = {"messaging.system": "aws_sqs", "messaging.destination.name": QUEUE_NAME}
        try:
            log.info("Processing SQS message", extra={"messaging.message.id": message.get("MessageId")})
            persist_message(message)
            messages_processed.add(1, metric_attributes)
        except Exception as error:
            # No acknowledgement on JSON/schema/storage/queue failures: allow retry.
            span.record_exception(error)
            span.set_status(Status(StatusCode.ERROR, type(error).__name__))
            span.set_attribute("error.type", type(error).__name__)
            messages_errors.add(1, {**metric_attributes, "error.type": type(error).__name__})
            log.error("SQS message processing failed", extra={"error.type": type(error).__name__})


def sqs_worker_loop():
    """ Loop principal do worker que ouve a fila SQS """
    log.info("Iniciando o worker SQS...")
    while True:
        try:
            # Long-polling: espera até 20s por mensagens
            response = sqs_client.receive_message(
                QueueUrl=SQS_QUEUE_URL,
                MaxNumberOfMessages=10,  # Processa em lotes de até 10
                WaitTimeSeconds=20,
                MessageAttributeNames=["traceparent", "tracestate"],
            )

            messages = response.get('Messages', [])
            if not messages:
                # Nenhuma mensagem, continua o loop
                continue

            log.info(f"Recebidas {len(messages)} mensagens.")

            for message in messages:
                process_message(message)

        except ClientError as e:
            log.error(f"Erro do Boto3 no loop principal do SQS: {e}")
            time.sleep(10)  # Pausa antes de tentar novamente
        except Exception as e:
            log.error(f"Erro inesperado no loop principal do SQS: {e}")
            time.sleep(10)


# --- Servidor Flask (Apenas para Health Check) ---

app = Flask(__name__)
telemetry.instrument_flask(app)


@app.route('/health')
def health():
    # Uma verificação de saúde real poderia checar a conexão com o DynamoDB/SQS
    return jsonify({"status": "ok"})

# --- Inicialização ---


def start_worker():
    """ Inicia o worker SQS em uma thread separada """
    worker_thread = threading.Thread(target=sqs_worker_loop, daemon=True)
    worker_thread.start()


# Inicia o worker SQS em uma thread de background
# Isso garante que ele inicie tanto com 'flask run' quanto com 'gunicorn'
start_worker()

if __name__ == '__main__':
    port = int(os.getenv("PORT", 8005))
    app.run(host='0.0.0.0', port=port, debug=False)
