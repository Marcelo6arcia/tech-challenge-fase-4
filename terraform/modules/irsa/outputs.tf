output "role_arn" {
  value       = aws_iam_role.this.arn
  description = "ARN da role — vai na annotation eks.amazonaws.com/role-arn do ServiceAccount"
}

output "role_name" {
  value       = aws_iam_role.this.name
  description = "Nome da role"
}
