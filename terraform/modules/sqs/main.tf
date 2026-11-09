# =============================================================================
# MÓDULO: sqs
# Fila de eventos: evaluation-service (produtor) -> analytics-service (consumidor).
# Inclui Dead Letter Queue para não perder mensagens que falham no processamento.
# =============================================================================

resource "aws_sqs_queue" "dlq" {
  count = var.enable_dlq ? 1 : 0

  name                      = "${var.queue_name}-dlq"
  message_retention_seconds = var.dlq_retention_seconds
  sqs_managed_sse_enabled   = true

  tags = merge(var.tags, { Name = "${var.queue_name}-dlq" })
}

resource "aws_sqs_queue" "this" {
  name = var.queue_name

  message_retention_seconds  = var.message_retention_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds # long polling reduz custo e latência
  sqs_managed_sse_enabled    = true

  redrive_policy = var.enable_dlq ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[0].arn
    maxReceiveCount     = var.max_receive_count
  }) : null

  tags = merge(var.tags, {
    Name     = var.queue_name
    Producer = "evaluation-service"
    Consumer = "analytics-service"
  })
}
