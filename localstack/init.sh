#!/bin/bash
set -e

echo ">>> Criando fila SQS: feature-flag-events"
awslocal sqs create-queue \
  --queue-name feature-flag-events \
  --region us-east-1

echo ">>> Criando tabela DynamoDB: analytics-events"
awslocal dynamodb create-table \
  --table-name analytics-events \
  --attribute-definitions \
    AttributeName=event_id,AttributeType=S \
    AttributeName=timestamp,AttributeType=S \
  --key-schema \
    AttributeName=event_id,KeyType=HASH \
    AttributeName=timestamp,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1

echo ">>> LocalStack: recursos criados com sucesso."
