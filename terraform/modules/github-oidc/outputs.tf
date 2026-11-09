output "role_arn" {
  value       = aws_iam_role.ci.arn
  description = "ARN a configurar no secret AWS_ROLE_ARN do repositório GitHub"
}

output "account_id" {
  value       = data.aws_caller_identity.current.account_id
  description = "Account ID da AWS"
}

output "apply_role_arn" {
  value       = var.enable_apply_role ? aws_iam_role.apply[0].arn : null
  description = "ARN a configurar no secret AWS_ROLE_ARN_APPLY do repositório GitHub"
}
