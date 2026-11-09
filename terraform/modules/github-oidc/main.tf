# =============================================================================
# MÓDULO: github-oidc
# Federação OIDC entre o GitHub Actions e a AWS.
# =============================================================================
#
# Elimina AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY dos secrets do repositório.
# O workflow recebe um token OIDC de vida curta emitido pelo próprio GitHub e o
# troca por credenciais temporárias na AWS. Uma chave estática vazada continua
# valendo até ser revogada; um token OIDC expira em minutos e só é emitido para
# os repositórios/branches declarados na condição de trust abaixo.
# =============================================================================

data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # Thumbprint da CA da Actions. A AWS valida a cadeia TLS desde 2023, mas o
  # campo continua obrigatório na API.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = var.tags
}

locals {
  oidc_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_oidc_provider_arn

  # Only the default workspace and the two phase-4 states are supported.
  # No wildcard may expose states from earlier phases in the shared bucket.
  state_keys      = [for name in ["infra", "platform"] : "${var.state_key_prefix}/${name}.tfstate"]
  state_lock_keys = [for key in local.state_keys : "${key}.tflock"]
  state_arns      = [for key in local.state_keys : "arn:aws:s3:::${var.state_bucket_name}/${key}"]
  state_lock_arns = [for key in local.state_lock_keys : "arn:aws:s3:::${var.state_bucket_name}/${key}"]
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restringe quais repositórios e refs podem assumir a role
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = var.allowed_subjects
    }
  }
}

resource "aws_iam_role" "ci" {
  name                 = var.role_name
  description          = "Role assumida pelo GitHub Actions via OIDC"
  assume_role_policy   = data.aws_iam_policy_document.assume_role.json
  max_session_duration = 3600

  tags = merge(var.tags, { Name = var.role_name })
}

# --- Push de imagens no ECR ---------------------------------------------------
data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "ECRAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeImageScanFindings",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = var.ecr_repository_arns
  }
}

resource "aws_iam_policy" "ecr_push" {
  name        = "${var.role_name}-ecr-push"
  description = "Push de imagens nos repositorios ECR do ToggleMaster"
  policy      = data.aws_iam_policy_document.ecr_push.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecr_push" {
  role       = aws_iam_role.ci.name
  policy_arn = aws_iam_policy.ecr_push.arn
}

# --- Terraform plan no CI (somente leitura + state) ---------------------------
data "aws_iam_policy_document" "terraform_plan" {
  count = var.enable_terraform_plan_access ? 1 : 0

  statement {
    sid       = "ListPhase4StateKeys"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.state_bucket_name}"]

    condition {
      test     = "StringEquals"
      variable = "s3:prefix"
      values   = concat(local.state_keys, local.state_lock_keys)
    }
  }

  statement {
    sid       = "ReadPhase4States"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = local.state_arns
  }

  # Plan can acquire/release locks, but cannot write or delete actual states.
  statement {
    sid       = "ManagePhase4StateLocks"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = local.state_lock_arns
  }

  statement {
    sid    = "ReadOnlyForPlan"
    effect = "Allow"
    # O provider da AWS le as tags de cada recurso ao atualizar o state, e a
    # politica so tinha Describe* para varios servicos. O plan morria em
    # AccessDenied sobre rds:ListTagsForResource, ecr:ListTagsForResource,
    # dynamodb:ListTagsOfResource, logs:ListTagsForResource,
    # elasticache:ListTagsForResource e secretsmanager:GetResourcePolicy.
    #
    # Os verbos de leitura ficam completos por servico, mas sem nada que leia
    # DADOS: nao existe secretsmanager:Get* aqui, porque isso arrastaria
    # GetSecretValue e daria ao CI de plan as senhas dos bancos. O acesso ao
    # segredo continua sendo so do External Secrets, via IRSA. Pelo mesmo
    # motivo nao existe dynamodb:Get*, que arrastaria GetItem -- as tags vem
    # de dynamodb:List*, que cobre ListTagsOfResource.
    actions = [
      "dynamodb:Describe*",
      "dynamodb:List*",
      "ec2:Describe*",
      "ecr:Describe*",
      "ecr:GetLifecyclePolicy",
      "ecr:List*",
      "eks:Describe*",
      "eks:List*",
      "elasticache:Describe*",
      "elasticache:List*",
      "iam:Get*",
      "iam:List*",
      "logs:Describe*",
      "logs:List*",
      "rds:Describe*",
      "rds:List*",
      "secretsmanager:Describe*",
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:List*",
      "sqs:Get*",
      "sqs:List*",
    ]
    resources = ["*"]
  }

  # O Terraform e dono do valor destes segredos: ele gera as senhas e cria os
  # aws_secretsmanager_secret_version. Para atualizar o state desses recursos o
  # provider chama GetSecretValue, entao nao existe plan funcional sem esta
  # permissao -- e consequencia de quem gera o segredo, nao de como a politica
  # foi escrita.
  #
  # Fica num statement separado, restrito aos ARNs exatos, e nunca em "*": o
  # statement acima vale para a conta inteira, e juntar as duas coisas daria
  # leitura de qualquer segredo da conta, hoje e no futuro.
  #
  # A forma de nao precisar disso e o valor nunca entrar no state, com os
  # write-only arguments do Terraform 1.11+ (secret_string_wo). E a postura
  # correta, e fica registrada aqui como divida tecnica consciente.
  dynamic "statement" {
    for_each = length(var.plan_readable_secret_arns) > 0 ? [1] : []

    content {
      sid       = "ReadManagedSecretValuesForPlan"
      effect    = "Allow"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = var.plan_readable_secret_arns
    }
  }
}

resource "aws_iam_policy" "terraform_plan" {
  count = var.enable_terraform_plan_access ? 1 : 0

  name        = "${var.role_name}-terraform-plan"
  description = "Leitura do estado e dos recursos para rodar terraform plan no CI"
  policy      = data.aws_iam_policy_document.terraform_plan[0].json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "terraform_plan" {
  count = var.enable_terraform_plan_access ? 1 : 0

  role       = aws_iam_role.ci.name
  policy_arn = aws_iam_policy.terraform_plan[0].arn
}
