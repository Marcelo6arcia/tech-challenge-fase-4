variable "aws_region" {
  description = "Região da AWS"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Profile do AWS CLI"
  type        = string
  default     = null
}

variable "infra_state_config" {
  description = <<-EOT
    Configuração do backend S3 onde está o state da camada infra. Exemplo:
      {
        bucket  = "togglemaster-tfstate-xxxxxxxx"
        key     = "togglemaster/fase4/infra.tfstate"
        region  = "us-east-1"
        profile = "fiap"
      }
  EOT
  type        = map(string)
}

variable "app_namespace" {
  description = "Namespace das aplicações"
  type        = string
  default     = "togglemaster"
}

variable "argocd_namespace" {
  description = "Namespace do Argo CD"
  type        = string
  default     = "argocd"
}

variable "gitops_repo_url" {
  description = "URL do repositório GitOps (ex.: https://github.com/Marcelo6arcia/togglemaster-gitops-fase-4.git)"
  type        = string
}

variable "gitops_repo_revision" {
  description = "Branch acompanhada pelo Argo CD"
  type        = string
  default     = "main"
}

variable "gitops_root_path" {
  description = "Caminho do app-of-apps dentro do repositório GitOps"
  type        = string
  default     = "argocd/applications"
}

variable "gitops_repo_private" {
  description = "true se o repositório GitOps for privado"
  type        = bool
  default     = false
}

variable "gitops_repo_username" {
  description = "Usuário para repositório GitOps privado"
  type        = string
  default     = ""
}

variable "gitops_repo_token" {
  description = "PAT de leitura do repositório GitOps privado (injete via TF_VAR_gitops_repo_token)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "argocd_ingress_enabled" {
  description = "Expõe a UI do Argo CD por Ingress"
  type        = bool
  default     = false
}

variable "argocd_hostname" {
  description = "Hostname do Ingress do Argo CD"
  type        = string
  default     = "argocd.local"
}
