# Fase 4: armazenamento persistente e referências de segredos da observabilidade.
# Valores de APM/PagerDuty/Discord são cadastrados no Secrets Manager pelo operador;
# não entram em tfvars, Git ou outputs. Este arquivo não provisiona nada sem apply.
resource "aws_secretsmanager_secret" "observability_apm" {
  name                    = "${local.secret_prefix}/observability/apm"
  description             = "NEW_RELIC_LICENSE_KEY da conta academica"
  recovery_window_in_days = 7
  tags                    = local.common_tags
}

resource "aws_secretsmanager_secret" "observability_incidents" {
  name                    = "${local.secret_prefix}/observability/incidents"
  description             = "RESPONDER_TOKEN, PAGERDUTY_INTEGRATION_KEY e DISCORD_WEBHOOK_URL"
  recovery_window_in_days = 7
  tags                    = local.common_tags
}

resource "aws_secretsmanager_secret" "observability_grafana" {
  name                    = "${local.secret_prefix}/observability/grafana"
  description             = "Credencial administrativa do Grafana academico"
  recovery_window_in_days = 7
  tags                    = local.common_tags
}

resource "random_password" "grafana_admin" {
  length  = 40
  special = false
}

resource "aws_secretsmanager_secret_version" "observability_grafana" {
  secret_id = aws_secretsmanager_secret.observability_grafana.id
  secret_string = jsonencode({
    admin-user     = "admin"
    admin-password = random_password.grafana_admin.result
  })
}

# A policy V2 oficial restringe mutações a volumes/snapshots marcados pelo CSI.
# A role é assumível somente por kube-system/ebs-csi-controller-sa deste cluster.
# Referência: https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html
# Sem permissões adicionais para snapshots/KMS customizado.
data "aws_iam_policy" "ebs_csi" {
  arn = "arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicyV2"
}

module "irsa_ebs_csi" {
  source = "../../../modules/irsa"

  role_name            = "${local.name_prefix}-ebs-csi"
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  namespace            = "kube-system"
  service_account_name = "ebs-csi-controller-sa"
  policy_json          = data.aws_iam_policy.ebs_csi.policy
  tags                 = local.common_tags
}

data "aws_eks_addon_version" "ebs_csi" {
  addon_name         = "aws-ebs-csi-driver"
  kubernetes_version = local.kubernetes_version
  most_recent        = true
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = data.aws_eks_addon_version.ebs_csi.version
  service_account_role_arn    = module.irsa_ebs_csi.role_arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  tags                        = local.common_tags
}

output "observability_secret_names" {
  description = "Nomes dos segredos; nao expoe os valores"
  value = {
    apm       = aws_secretsmanager_secret.observability_apm.name
    incidents = aws_secretsmanager_secret.observability_incidents.name
    grafana   = aws_secretsmanager_secret.observability_grafana.name
  }
}
