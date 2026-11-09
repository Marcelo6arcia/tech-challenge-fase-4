# =============================================================================
# MÓDULO: irsa (IAM Roles for Service Accounts)
# Cria uma role IAM que só pode ser assumida por UM ServiceAccount específico,
# em UM namespace específico, do cluster EKS deste ambiente.
# =============================================================================
#
# Por que isso importa: na Fase 2, as permissões de SQS e DynamoDB estavam
# anexadas à role dos nós — ou seja, QUALQUER pod do cluster podia ler a fila e
# escrever na tabela. Com IRSA, o token do ServiceAccount é trocado por
# credenciais temporárias com escopo mínimo, e apenas o pod dono do
# ServiceAccount consegue fazer essa troca.
# =============================================================================

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.role_name
  description        = "IRSA para ${var.namespace}/${var.service_account_name}"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = merge(var.tags, {
    Name           = var.role_name
    ServiceAccount = "${var.namespace}/${var.service_account_name}"
  })
}

resource "aws_iam_policy" "this" {
  name        = "${var.role_name}-policy"
  description = "Permissoes minimas de ${var.namespace}/${var.service_account_name}"
  policy      = var.policy_json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.this.arn
}
