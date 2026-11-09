variable "role_name" {
  description = "Nome da role assumida pelo GitHub Actions"
  type        = string
  default     = "togglemaster-github-actions"
}

variable "create_oidc_provider" {
  description = "Cria o OIDC provider do GitHub. Use false se a conta já tiver um."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "ARN do OIDC provider existente (quando create_oidc_provider = false)"
  type        = string
  default     = null
}

variable "allowed_subjects" {
  description = <<-EOT
    Padrões de "sub" do token OIDC autorizados a assumir a role.
    Exemplos:
      repo:Marcelo6arcia/tech-challenge-fase-4:ref:refs/heads/main
      repo:Marcelo6arcia/tech-challenge-fase-4:pull_request
      repo:Marcelo6arcia/tech-challenge-fase-4:*   (qualquer ref do repositório)
  EOT
  type        = list(string)
}

variable "ecr_repository_arns" {
  description = "ARNs dos repositórios ECR onde o CI pode publicar imagens"
  type        = list(string)
}

variable "enable_terraform_plan_access" {
  description = "Concede leitura do state S3 e dos recursos para rodar terraform plan no CI"
  type        = bool
  default     = true
}

variable "state_bucket_name" {
  description = "Nome do bucket de state (necessário quando enable_terraform_plan_access = true)"
  type        = string
  default     = ""
}

variable "state_key_prefix" {
  description = "Prefixo exclusivo dos states infra/platform da fase 4, sem barra inicial/final ou curingas"
  type        = string
  default     = "togglemaster/fase4"

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*$", var.state_key_prefix))
    error_message = "state_key_prefix deve conter segmentos ASCII separados por /, sem curingas ou barras nas extremidades."
  }
}

variable "tags" {
  description = "Tags aplicadas aos recursos"
  type        = map(string)
  default     = {}
}

variable "enable_apply_role" {
  description = "Cria uma segunda role, privilegiada, para o job de terraform apply"
  type        = bool
  default     = true
}

variable "apply_role_subjects" {
  description = <<-EOT
    Subjects OIDC autorizados a assumir a role de apply. Use sempre o formato de
    environment — `repo:<owner>/<repo>:environment:<nome>` — e nunca um ref de
    branch: é a aprovação exigida pelo GitHub Environment que serve de porta,
    e ela é configuração do repositório, que um pull request não altera.
  EOT
  type        = list(string)
  default     = []
}

variable "project_prefix" {
  description = "Prefixo dos nomes de role e policy que a role de apply pode gerenciar"
  type        = string
  default     = "togglemaster"
}

variable "plan_readable_secret_arns" {
  description = "ARNs dos segredos que o terraform plan precisa ler para atualizar o state."
  type        = list(string)
  default     = []
}
