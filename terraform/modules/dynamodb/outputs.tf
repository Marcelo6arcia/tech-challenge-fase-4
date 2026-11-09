output "table_name" {
  value       = aws_dynamodb_table.this.name
  description = "Nome da tabela"
}

output "table_arn" {
  value       = aws_dynamodb_table.this.arn
  description = "ARN da tabela"
}

output "table_index_arns" {
  value       = ["${aws_dynamodb_table.this.arn}/index/*"]
  description = "ARNs dos índices — necessários nas policies IRSA"
}
