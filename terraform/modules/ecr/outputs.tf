output "repository_urls" {
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
  description = "URL de cada repositório, por serviço"
}

output "repository_arns" {
  value       = [for r in aws_ecr_repository.this : r.arn]
  description = "ARNs dos repositórios — usados na policy do papel OIDC do GitHub Actions"
}

output "registry_url" {
  value       = length(var.repository_names) > 0 ? split("/", values(aws_ecr_repository.this)[0].repository_url)[0] : null
  description = "Host do registry (<account>.dkr.ecr.<region>.amazonaws.com)"
}
