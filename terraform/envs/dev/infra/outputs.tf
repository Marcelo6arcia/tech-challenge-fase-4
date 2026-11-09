# =============================================================================
# Outputs
# =============================================================================
# Nenhum output expõe senha: as credenciais ficam no Secrets Manager e chegam
# ao cluster pelo External Secrets Operator.
# =============================================================================

output "aws_account_id" {
  value       = data.aws_caller_identity.current.account_id
  description = "Account ID da AWS"
}

output "aws_region" {
  value       = var.aws_region
  description = "Região usada pelo ambiente"
}

# --- Rede --------------------------------------------------------------------
output "vpc_id" {
  value       = module.network.vpc_id
  description = "ID da VPC"
}

output "public_subnet_ids" {
  value       = module.network.public_subnet_ids
  description = "Subnets públicas"
}

output "private_subnet_ids" {
  value       = module.network.private_subnet_ids
  description = "Subnets privadas"
}

# --- EKS ---------------------------------------------------------------------
output "eks_cluster_name" {
  value       = module.eks.cluster_name
  description = "Nome do cluster — use em: aws eks update-kubeconfig --name <valor>"
}

output "eks_cluster_endpoint" {
  value       = module.eks.cluster_endpoint
  description = "Endpoint da API do cluster"
}

output "eks_kubernetes_version" {
  value = {
    versao                = local.kubernetes_version
    status                = lookup(local.status_por_versao, local.kubernetes_version, "desconhecido")
    fim_do_suporte_padrao = lookup(local.fim_suporte_padrao, local.kubernetes_version, "desconhecido")
    versao_padrao_da_aws  = local.versao_padrao_eks
  }
  description = "Versão do Kubernetes em uso e até quando ela fica no suporte padrão"
}

output "eks_oidc_provider_arn" {
  value       = module.eks.oidc_provider_arn
  description = "OIDC provider do cluster"
}

output "kubeconfig_command" {
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name} --alias togglemaster-fase4 --profile fiap"
  description = "Comando para configurar o kubectl"
}

# --- Dados -------------------------------------------------------------------
output "rds_endpoints" {
  value = {
    auth      = module.rds_auth.endpoint
    flag      = module.rds_flag.endpoint
    targeting = module.rds_targeting.endpoint
  }
  description = "Endpoints das instâncias RDS"
}

output "redis_endpoint" {
  value       = module.redis.endpoint
  description = "Endpoint do ElastiCache Redis"
}

output "sqs_queue_url" {
  value       = module.sqs.queue_url
  description = "URL da fila SQS"
}

output "dynamodb_table_name" {
  value       = module.dynamodb.table_name
  description = "Nome da tabela DynamoDB"
}

# --- Segredos ----------------------------------------------------------------
output "secret_names" {
  value = {
    auth_database      = module.rds_auth.secret_name
    flag_database      = module.rds_flag.secret_name
    targeting_database = module.rds_targeting.secret_name
    auth_app           = aws_secretsmanager_secret.auth_app.name
    evaluation_app     = aws_secretsmanager_secret.evaluation_app.name
    analytics_app      = aws_secretsmanager_secret.analytics_app.name
  }
  description = "Nomes dos secrets no Secrets Manager — referenciados nos ExternalSecrets do repositório GitOps"
}

# --- ECR ---------------------------------------------------------------------
output "ecr_registry" {
  value       = module.ecr.registry_url
  description = "Host do registry ECR"
}

output "ecr_repository_urls" {
  value       = module.ecr.repository_urls
  description = "URL de cada repositório ECR"
}

# --- CI ----------------------------------------------------------------------
output "github_actions_role_arn" {
  value       = module.github_oidc.role_arn
  description = "Configure este ARN no secret AWS_ROLE_ARN do repositório GitHub"
}

output "github_actions_apply_role_arn" {
  value       = module.github_oidc.apply_role_arn
  description = "Configure este ARN no secret AWS_ROLE_ARN_APPLY do repositório GitHub"
}

# --- IRSA --------------------------------------------------------------------
output "irsa_role_arns" {
  value = {
    external_secrets   = module.irsa_external_secrets.role_arn
    evaluation_service = module.irsa_evaluation_service.role_arn
    analytics_service  = module.irsa_analytics_service.role_arn
  }
  description = "ARNs das roles IRSA — vão nas annotations dos ServiceAccounts no repositório GitOps"
}

# --- Resumo para o repositório GitOps ----------------------------------------
output "gitops_wiring" {
  description = "Valores a preencher no repositório GitOps (rode: terraform output -json gitops_wiring)"
  value = {
    aws_region             = var.aws_region
    aws_account_id         = data.aws_caller_identity.current.account_id
    ecr_registry           = module.ecr.registry_url
    app_namespace          = var.app_namespace
    secret_prefix          = local.secret_prefix
    evaluation_sa_role_arn = module.irsa_evaluation_service.role_arn
    analytics_sa_role_arn  = module.irsa_analytics_service.role_arn
    dynamodb_table         = module.dynamodb.table_name
    sqs_queue_url          = module.sqs.queue_url
  }
}
