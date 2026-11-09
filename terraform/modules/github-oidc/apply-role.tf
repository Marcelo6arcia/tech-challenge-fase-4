# =============================================================================
# Role de APPLY do Terraform no CI
# =============================================================================
#
# Separada da role de plan de propósito. A role `ci` acima é somente leitura:
# ela roda `terraform plan` em pull request e publica imagem no ECR, e um token
# vazado num PR de terceiro não consegue criar nada.
#
# Criar infraestrutura exige permissão ampla — não há como provisionar VPC, EKS
# e RDS com escopo estreito. Os três controles que tornam isso defensável são:
#
#   1. A condição de trust aceita SOMENTE o subject `environment:<nome>`. O
#      token só é emitido depois que o GitHub Environment aprova o job, e
#      environment protection rule é configuração do repositório, não do
#      workflow — um pull request não consegue alterá-la.
#   2. As ações de IAM são limitadas a recursos com o prefixo do projeto. Sem
#      isso, uma role que pode criar roles pode criar uma role de admin.
#   3. Um Deny explícito impede que a role altere a si mesma ou à role de plan.
#      Deny vence Allow em qualquer avaliação de política da AWS.
# =============================================================================

resource "aws_iam_role" "apply" {
  count = var.enable_apply_role ? 1 : 0

  name                 = "${var.role_name}-apply"
  description          = "Role de terraform apply, restrita ao GitHub Environment"
  assume_role_policy   = data.aws_iam_policy_document.assume_role_apply[0].json
  max_session_duration = 3600

  tags = merge(var.tags, { Name = "${var.role_name}-apply" })
}

data "aws_iam_policy_document" "assume_role_apply" {
  count = var.enable_apply_role ? 1 : 0

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

    # Diferença central para a role de plan: `StringEquals` com o subject de
    # environment, e não `StringLike` com curinga de branch.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = var.apply_role_subjects
    }
  }
}

data "aws_iam_policy_document" "terraform_apply" {
  count = var.enable_apply_role ? 1 : 0

  # --- Serviços que compõem a stack -----------------------------------------
  # Lista explícita em vez de "*": o inventário de serviços do projeto vira
  # documentação executável, e adicionar um serviço novo exige alterar aqui.
  statement {
    sid    = "ProvisionarStack"
    effect = "Allow"
    actions = [
      "autoscaling:*",
      "dynamodb:*",
      "ec2:*",
      "ecr:*",
      "eks:*",
      "elasticache:*",
      "elasticloadbalancing:*",
      "kms:CreateGrant",
      "kms:Describe*",
      "kms:Get*",
      "kms:List*",
      "logs:*",
      "rds:*",
      "secretsmanager:*",
      "sqs:*",
      "tag:Get*",
      "tag:TagResources",
      "tag:UntagResources",
    ]
    resources = ["*"]
  }

  # --- State remoto ----------------------------------------------------------
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
    sid       = "ReadWritePhase4States"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = local.state_arns
  }

  # DeleteObject belongs to locks only, never to the Terraform state objects.
  statement {
    sid       = "ManagePhase4StateLocks"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = local.state_lock_arns
  }

  # --- IAM, restrito ao prefixo do projeto -----------------------------------
  # Uma role que cria roles sem restrição de nome pode criar uma role de admin
  # e assumi-la. O prefixo é o que impede a escalação de privilégio.
  statement {
    sid    = "IAMDoProjeto"
    effect = "Allow"
    actions = [
      "iam:AttachRolePolicy",
      "iam:CreatePolicy",
      "iam:CreatePolicyVersion",
      "iam:CreateRole",
      "iam:CreateServiceLinkedRole",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:TagPolicy",
      "iam:TagRole",
      "iam:UntagPolicy",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_prefix}*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.project_prefix}*",
    ]
  }

  # PassRole é o que permite entregar a role dos nós ao EKS. Sem restrição de
  # recurso, permitiria entregar qualquer role da conta a qualquer serviço.
  statement {
    sid       = "PassRoleDoProjeto"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_prefix}*"]
  }

  # Leitura de IAM é necessária no refresh do plan e não concede nada.
  statement {
    sid       = "LerIAM"
    effect    = "Allow"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  # O provider OIDC do EKS é criado pelo módulo eks e não aceita prefixo de nome.
  statement {
    sid    = "ProviderOIDCDoEKS"
    effect = "Allow"
    actions = [
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/*"]
  }

  # --- Deny explícito sobre as próprias roles do CI --------------------------
  # Sem isto, a role de apply poderia anexar AdministratorAccess a si mesma ou
  # afrouxar a condição de trust da role de plan. Deny vence Allow.
  statement {
    sid    = "NaoAlterarAsProprias"
    effect = "Deny"
    actions = [
      "iam:AttachRolePolicy",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:UpdateAssumeRolePolicy",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.role_name}",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.role_name}-apply",
    ]
  }
}

resource "aws_iam_policy" "terraform_apply" {
  count = var.enable_apply_role ? 1 : 0

  name        = "${var.role_name}-terraform-apply"
  description = "Provisionamento da stack do ToggleMaster pelo CI"
  policy      = data.aws_iam_policy_document.terraform_apply[0].json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "terraform_apply" {
  count = var.enable_apply_role ? 1 : 0

  role       = aws_iam_role.apply[0].name
  policy_arn = aws_iam_policy.terraform_apply[0].arn
}
