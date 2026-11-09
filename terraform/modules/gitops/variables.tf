variable "app_namespace" {
  description = "Namespace das aplicações do ToggleMaster"
  type        = string
  default     = "togglemaster"
}

variable "argocd_namespace" {
  description = "Namespace do Argo CD"
  type        = string
  default     = "argocd"
}

variable "argocd_chart_version" {
  description = "Versão do chart argo-cd"
  type        = string
  default     = "7.7.11"
}

variable "argocd_apps_chart_version" {
  description = "Versão do chart argocd-apps"
  type        = string
  default     = "2.0.2"
}

variable "argocd_hostname" {
  description = "Hostname do Ingress do Argo CD"
  type        = string
  default     = "argocd.local"
}

variable "argocd_ingress_enabled" {
  description = "Expõe a UI do Argo CD via Ingress. Com false, use kubectl port-forward."
  type        = bool
  default     = false
}

variable "install_ingress_nginx" {
  description = "Instala o ingress-nginx"
  type        = bool
  default     = true
}

variable "ingress_nginx_chart_version" {
  description = "Versão do chart ingress-nginx"
  type        = string
  default     = "4.11.3"
}

variable "install_external_secrets" {
  description = "Instala o External Secrets Operator"
  type        = bool
  default     = true
}

variable "external_secrets_chart_version" {
  description = "Versão do chart external-secrets"
  type        = string
  default     = "0.10.5"
}

variable "external_secrets_service_account" {
  description = "Nome do ServiceAccount do External Secrets (deve bater com a condição da role IRSA)"
  type        = string
  default     = "external-secrets"
}

variable "external_secrets_role_arn" {
  description = "ARN da role IRSA que dá acesso de leitura ao Secrets Manager"
  type        = string
}

variable "gitops_repo_url" {
  description = "URL do repositório GitOps monitorado pelo Argo CD"
  type        = string
}

variable "gitops_repo_revision" {
  description = "Branch ou tag acompanhada pelo Argo CD"
  type        = string
  default     = "main"
}

variable "gitops_root_path" {
  description = "Caminho, dentro do repositório GitOps, com as Applications (app-of-apps)"
  type        = string
  default     = "argocd/applications"
}

variable "gitops_repo_private" {
  description = "Cria o secret de credenciais do repositório (apenas para repositório privado)"
  type        = bool
  default     = false
}

variable "gitops_repo_username" {
  description = "Usuário do repositório GitOps privado"
  type        = string
  default     = ""
}

variable "gitops_repo_token" {
  description = "Personal Access Token de leitura do repositório GitOps privado"
  type        = string
  default     = ""
  sensitive   = true
}
