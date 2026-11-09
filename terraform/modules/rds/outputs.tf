output "endpoint" {
  value       = aws_db_instance.this.address
  description = "Hostname da instância RDS"
}

output "port" {
  value       = aws_db_instance.this.port
  description = "Porta da instância"
}

output "db_name" {
  value       = aws_db_instance.this.db_name
  description = "Nome do banco"
}

output "security_group_id" {
  value       = aws_security_group.this.id
  description = "Security group da instância"
}

output "secret_arn" {
  value       = aws_secretsmanager_secret.db.arn
  description = "ARN do secret com as credenciais"
}

output "secret_name" {
  value       = aws_secretsmanager_secret.db.name
  description = "Nome do secret — referenciado no ExternalSecret do repositório GitOps"
}
