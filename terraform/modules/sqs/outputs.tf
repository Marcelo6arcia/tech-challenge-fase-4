output "queue_url" {
  value       = aws_sqs_queue.this.url
  description = "URL da fila principal"
}

output "queue_arn" {
  value       = aws_sqs_queue.this.arn
  description = "ARN da fila principal"
}

output "queue_name" {
  value       = aws_sqs_queue.this.name
  description = "Nome da fila principal"
}

output "dlq_arn" {
  value       = try(aws_sqs_queue.dlq[0].arn, null)
  description = "ARN da DLQ"
}
