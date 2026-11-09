# =============================================================================
# AMBIENTE dev — camada de PLATAFORMA
# Instala no cluster: ingress-nginx, External Secrets Operator, Argo CD e a
# Application raiz que aponta para o repositório GitOps.
# =============================================================================

module "gitops" {
  source = "../../../modules/gitops"

  app_namespace    = var.app_namespace
  argocd_namespace = var.argocd_namespace

  install_ingress_nginx    = true
  install_external_secrets = true

  external_secrets_role_arn = data.terraform_remote_state.infra.outputs.irsa_role_arns.external_secrets

  gitops_repo_url      = var.gitops_repo_url
  gitops_repo_revision = var.gitops_repo_revision
  gitops_root_path     = var.gitops_root_path

  gitops_repo_private  = var.gitops_repo_private
  gitops_repo_username = var.gitops_repo_username
  gitops_repo_token    = var.gitops_repo_token

  argocd_ingress_enabled = var.argocd_ingress_enabled
  argocd_hostname        = var.argocd_hostname
}
