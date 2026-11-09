# =============================================================================
# AMBIENTE dev — camada de INFRAESTRUTURA
# =============================================================================
# Ordem de execução do projeto:
#   1. terraform/bootstrap        -> cria o bucket S3 do state
#   2. terraform/envs/dev/infra   -> ESTE módulo (rede, EKS, dados, ECR, IAM)
#   3. terraform/envs/dev/platform-> Argo CD, ingress-nginx, External Secrets
#   4. repositório GitOps         -> as 5 aplicações, sincronizadas pelo Argo CD
# =============================================================================

data "aws_caller_identity" "current" {}

# =============================================================================
# VERSÃO DO KUBERNETES — descoberta, não chutada
# =============================================================================
# Fixar "1.31" no código funciona no dia em que se escreve e envelhece sozinho.
# O problema não é estético: quando uma versão sai do suporte padrão do EKS, o
# control plane passa de US$ 0,10 para US$ 0,60 por hora — de ~US$ 73 para
# ~US$ 438 por mês, sem nenhum aviso no `apply`.
#
# Por isso a versão vem do próprio EKS. Sem `kubernetes_version` definido, usa-se
# a versão padrão da AWS, que está sempre em suporte padrão e é a mais bem
# coberta pelos add-ons.
data "aws_eks_cluster_versions" "padrao" {
  cluster_type = "eks"
  default_only = true
}

# Lista completa, usada só para validar a escolha (inclusive quando alguém fixa
# uma versão à mão no terraform.tfvars).
data "aws_eks_cluster_versions" "todas" {
  cluster_type = "eks"
  include_all  = true
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # Versão do EKS: a fixada no tfvars, ou a padrão da AWS quando não houver
  versao_padrao_eks  = data.aws_eks_cluster_versions.padrao.cluster_versions[0].cluster_version
  kubernetes_version = coalesce(var.kubernetes_version, local.versao_padrao_eks)

  status_por_versao = {
    for v in data.aws_eks_cluster_versions.todas.cluster_versions :
    v.cluster_version => v.version_status
  }
  fim_suporte_padrao = {
    for v in data.aws_eks_cluster_versions.todas.cluster_versions :
    v.cluster_version => v.end_of_standard_support_date
  }

  services = [
    "auth-service",
    "flag-service",
    "targeting-service",
    "evaluation-service",
    "analytics-service",
  ]

  secret_prefix = "${var.project_name}/${var.environment}"

  common_tags = {
    Project     = "ToggleMaster"
    Environment = var.environment
    Phase       = "4"
    ManagedBy   = "Terraform"
    Repository  = "${var.github_owner}/${var.github_app_repo}"
  }

  # Formato antigo e formato novo do subject do OIDC do GitHub.
  github_repo_refs = concat(
    ["${var.github_owner}/${var.github_app_repo}"],
    var.github_repo_id == "" ? [] : ["${var.github_owner}@${var.github_owner_id}/${var.github_app_repo}@${var.github_repo_id}"]
  )
}

# -----------------------------------------------------------------------------
# Guarda de custo: recusa versão fora do suporte padrão
# -----------------------------------------------------------------------------
# O `apply` falha aqui, em segundos, em vez de subir um cluster que custa seis
# vezes mais no control plane e só aparece na fatura no mês seguinte.
resource "terraform_data" "guarda_versao_eks" {
  input = local.kubernetes_version

  lifecycle {
    precondition {
      condition     = lookup(local.status_por_versao, local.kubernetes_version, "UNSUPPORTED") == "STANDARD_SUPPORT"
      error_message = <<-EOT
        A versão ${local.kubernetes_version} do Kubernetes está em
        "${lookup(local.status_por_versao, local.kubernetes_version, "UNSUPPORTED")}" no EKS.

        Fora do suporte padrão o control plane custa US$ 0,60/hora em vez de
        US$ 0,10/hora — cerca de US$ 438/mês contra US$ 73/mês.

        A versão padrão da AWS hoje é ${local.versao_padrao_eks}. Remova
        `kubernetes_version` do terraform.tfvars para usá-la automaticamente.
      EOT
    }
  }
}

# -----------------------------------------------------------------------------
# Rede
# -----------------------------------------------------------------------------
module "network" {
  source = "../../../modules/network"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  az_count           = 2
  enable_nat_gateway = var.enable_nat_gateway
  enable_flow_logs   = true

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Cluster EKS
# -----------------------------------------------------------------------------
module "eks" {
  source = "../../../modules/eks"

  cluster_name       = "${local.name_prefix}-eks"
  kubernetes_version = local.kubernetes_version

  subnet_ids = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  # Sem NAT Gateway, os nós precisam de rota direta para a internet (pull de
  # imagens do ECR, add-ons). Com enable_nat_gateway = true, mova para privadas.
  node_subnet_ids = var.enable_nat_gateway ? module.network.private_subnet_ids : module.network.public_subnet_ids

  node_instance_types = var.node_instance_types
  node_min_size       = var.node_min_size
  node_desired_size   = var.node_desired_size
  node_max_size       = var.node_max_size

  cluster_admin_principal_arns = concat(
    var.cluster_admin_principal_arns,
    [
      for usuario in var.cluster_admin_iam_users :
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${usuario}"
    ]
  )
  public_access_cidrs = var.public_access_cidrs

  tags = local.common_tags

  depends_on = [terraform_data.guarda_versao_eks]
}

# -----------------------------------------------------------------------------
# Subnet group compartilhado pelas 3 instâncias RDS
# -----------------------------------------------------------------------------
resource "aws_db_subnet_group" "shared" {
  name       = "${local.name_prefix}-rds-subnet-group"
  subnet_ids = module.network.private_subnet_ids

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-rds-subnet-group" })
}

# -----------------------------------------------------------------------------
# Bancos de dados — 3 instâncias PostgreSQL
# -----------------------------------------------------------------------------
module "rds_auth" {
  source = "../../../modules/rds"

  identifier = "${local.name_prefix}-auth-db"
  service    = "auth-service"
  db_name    = "authdb"
  username   = "authuser"

  vpc_id                  = module.network.vpc_id
  vpc_cidr                = module.network.vpc_cidr
  db_subnet_group_name    = aws_db_subnet_group.shared.name
  allowed_security_groups = { eks_cluster = module.eks.cluster_security_group_id }

  engine_version     = var.postgres_version
  instance_class     = var.rds_instance_class
  secret_name_prefix = local.secret_prefix

  tags = local.common_tags
}

module "rds_flag" {
  source = "../../../modules/rds"

  identifier = "${local.name_prefix}-flag-db"
  service    = "flag-service"
  db_name    = "flagdb"
  username   = "flaguser"

  vpc_id                  = module.network.vpc_id
  vpc_cidr                = module.network.vpc_cidr
  db_subnet_group_name    = aws_db_subnet_group.shared.name
  allowed_security_groups = { eks_cluster = module.eks.cluster_security_group_id }

  engine_version     = var.postgres_version
  instance_class     = var.rds_instance_class
  secret_name_prefix = local.secret_prefix

  tags = local.common_tags
}

module "rds_targeting" {
  source = "../../../modules/rds"

  identifier = "${local.name_prefix}-targeting-db"
  service    = "targeting-service"
  db_name    = "targetingdb"
  username   = "targetinguser"

  vpc_id                  = module.network.vpc_id
  vpc_cidr                = module.network.vpc_cidr
  db_subnet_group_name    = aws_db_subnet_group.shared.name
  allowed_security_groups = { eks_cluster = module.eks.cluster_security_group_id }

  engine_version     = var.postgres_version
  instance_class     = var.rds_instance_class
  secret_name_prefix = local.secret_prefix

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Cache e mensageria
# -----------------------------------------------------------------------------
module "redis" {
  source = "../../../modules/elasticache"

  name                    = local.name_prefix
  vpc_id                  = module.network.vpc_id
  vpc_cidr                = module.network.vpc_cidr
  subnet_ids              = module.network.private_subnet_ids
  allowed_security_groups = { eks_cluster = module.eks.cluster_security_group_id }

  tags = local.common_tags
}

module "sqs" {
  source = "../../../modules/sqs"

  queue_name = var.sqs_queue_name
  enable_dlq = true

  tags = local.common_tags
}

module "dynamodb" {
  source = "../../../modules/dynamodb"

  table_name = var.dynamodb_table_name

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Registro de imagens
# -----------------------------------------------------------------------------
module "ecr" {
  source = "../../../modules/ecr"

  repository_names = concat(local.services, ["incident-responder"])
  keep_last_images = 10

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Federação OIDC com o GitHub Actions (sem access key estática)
# -----------------------------------------------------------------------------
module "github_oidc" {
  source = "../../../modules/github-oidc"

  role_name = "${local.name_prefix}-github-actions"

  # O GitHub passou a emitir o subject com os IDs numericos imutaveis de owner e
  # repositorio: repo:owner@71568242/repo@1363085368:ref:refs/heads/main. A trust
  # policy so conhecia o formato antigo, e todo job que falava com a AWS morria
  # em "Not authorized to perform sts:AssumeRoleWithWebIdentity". Os dois
  # formatos ficam autorizados, cada um por extenso.
  #
  # CI de publicação/plan somente na main; PR não recebe acesso ao state,
  # segredos ou ECR. Apply usa a role separada do environment aws-dev.
  # De proposito sem curinga no nome: "repo:${var.github_owner}*" casaria com
  # um owner de prefixo igual e nome maior, que poderia assumir estas roles.
  allowed_subjects = flatten([
    for referencia in local.github_repo_refs : [
      "repo:${referencia}:ref:refs/heads/main",
    ]
  ])

  # Somente o subject de environment: a role privilegiada só é assumível depois
  # da aprovação configurada no GitHub Environment `aws-dev`.
  apply_role_subjects = [
    for referencia in local.github_repo_refs : "repo:${referencia}:environment:aws-dev"
  ]

  plan_readable_secret_arns = [
    module.rds_auth.secret_arn,
    module.rds_flag.secret_arn,
    module.rds_targeting.secret_arn,
    aws_secretsmanager_secret.auth_app.arn,
    aws_secretsmanager_secret.evaluation_app.arn,
    aws_secretsmanager_secret.analytics_app.arn,
    aws_secretsmanager_secret.observability_apm.arn,
    aws_secretsmanager_secret.observability_incidents.arn,
    aws_secretsmanager_secret.observability_grafana.arn,
  ]

  ecr_repository_arns          = module.ecr.repository_arns
  enable_terraform_plan_access = var.state_bucket_name != ""
  state_bucket_name            = var.state_bucket_name
  project_prefix               = local.name_prefix

  tags = local.common_tags
}

# =============================================================================
# SEGREDOS DA APLICAÇÃO
# =============================================================================
# Gerados aqui e guardados no Secrets Manager. Nenhum valor sensível é escrito
# em arquivo YAML, .tfvars ou variável de ambiente do repositório.
# -----------------------------------------------------------------------------

resource "random_password" "master_key" {
  length  = 40
  special = false
}

# Chave de serviço usada pelo evaluation-service ao chamar flag/targeting.
# O auth-service guarda apenas o SHA-256 (ver auth-service/key.go), então o
# hash é calculado aqui e semeado no banco pelo Job de migração do GitOps.
resource "random_id" "service_api_key" {
  byte_length = 32
}

locals {
  service_api_key      = "tm_key_${random_id.service_api_key.hex}"
  service_api_key_hash = sha256(local.service_api_key)
}

resource "aws_secretsmanager_secret" "auth_app" {
  name                    = "${local.secret_prefix}/auth-service/app"
  description             = "Segredos de aplicacao do auth-service"
  recovery_window_in_days = 0

  tags = merge(local.common_tags, { Service = "auth-service" })
}

resource "aws_secretsmanager_secret_version" "auth_app" {
  secret_id = aws_secretsmanager_secret.auth_app.id

  secret_string = jsonencode({
    MASTER_KEY = random_password.master_key.result
    # Consumido pelo Job de bootstrap para cadastrar a chave do evaluation-service
    SERVICE_API_KEY_HASH = local.service_api_key_hash
  })
}

resource "aws_secretsmanager_secret" "evaluation_app" {
  name                    = "${local.secret_prefix}/evaluation-service/app"
  description             = "Segredos de aplicacao do evaluation-service"
  recovery_window_in_days = 0

  tags = merge(local.common_tags, { Service = "evaluation-service" })
}

resource "aws_secretsmanager_secret_version" "evaluation_app" {
  secret_id = aws_secretsmanager_secret.evaluation_app.id

  secret_string = jsonencode({
    REDIS_URL       = module.redis.redis_url
    AWS_SQS_URL     = module.sqs.queue_url
    SERVICE_API_KEY = local.service_api_key
  })
}

resource "aws_secretsmanager_secret" "analytics_app" {
  name                    = "${local.secret_prefix}/analytics-service/app"
  description             = "Configuracao do analytics-service"
  recovery_window_in_days = 0

  tags = merge(local.common_tags, { Service = "analytics-service" })
}

resource "aws_secretsmanager_secret_version" "analytics_app" {
  secret_id = aws_secretsmanager_secret.analytics_app.id

  secret_string = jsonencode({
    AWS_SQS_URL        = module.sqs.queue_url
    AWS_DYNAMODB_TABLE = module.dynamodb.table_name
    AWS_REGION         = var.aws_region
  })
}

# =============================================================================
# IRSA — uma role por workload, com o mínimo de permissões
# =============================================================================

# --- External Secrets Operator: lê os segredos acima -------------------------
data "aws_iam_policy_document" "external_secrets" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      module.rds_auth.secret_arn,
      module.rds_flag.secret_arn,
      module.rds_targeting.secret_arn,
      aws_secretsmanager_secret.auth_app.arn,
      aws_secretsmanager_secret.evaluation_app.arn,
      aws_secretsmanager_secret.analytics_app.arn,
      aws_secretsmanager_secret.observability_apm.arn,
      aws_secretsmanager_secret.observability_incidents.arn,
      aws_secretsmanager_secret.observability_grafana.arn,
    ]
  }

  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:ListSecrets"]
    resources = ["*"]
  }
}

module "irsa_external_secrets" {
  source = "../../../modules/irsa"

  role_name            = "${local.name_prefix}-external-secrets"
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  namespace            = "external-secrets"
  service_account_name = "external-secrets"
  policy_json          = data.aws_iam_policy_document.external_secrets.json

  tags = local.common_tags
}

# --- evaluation-service: só PUBLICA na fila ----------------------------------
data "aws_iam_policy_document" "evaluation_service" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:SendMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
    ]
    resources = [module.sqs.queue_arn]
  }
}

module "irsa_evaluation_service" {
  source = "../../../modules/irsa"

  role_name            = "${local.name_prefix}-evaluation-service"
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  namespace            = var.app_namespace
  service_account_name = "evaluation-service"
  policy_json          = data.aws_iam_policy_document.evaluation_service.json

  tags = local.common_tags
}

# --- analytics-service: só CONSOME a fila e escreve na tabela ----------------
data "aws_iam_policy_document" "analytics_service" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
    ]
    resources = [module.sqs.queue_arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:BatchWriteItem",
      "dynamodb:DescribeTable",
    ]
    resources = concat([module.dynamodb.table_arn], module.dynamodb.table_index_arns)
  }
}

module "irsa_analytics_service" {
  source = "../../../modules/irsa"

  role_name            = "${local.name_prefix}-analytics-service"
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  namespace            = var.app_namespace
  service_account_name = "analytics-service"
  policy_json          = data.aws_iam_policy_document.analytics_service.json

  tags = local.common_tags
}
