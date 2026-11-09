variable "role_name" {
  description = "Nome da role IAM"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN do OIDC provider do cluster EKS"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL do issuer OIDC sem o esquema https://"
  type        = string
}

variable "namespace" {
  description = "Namespace do ServiceAccount"
  type        = string
}

variable "service_account_name" {
  description = "Nome do ServiceAccount autorizado a assumir a role"
  type        = string
}

variable "policy_json" {
  description = "Documento de policy IAM (JSON) com as permissões concedidas"
  type        = string
}

variable "tags" {
  description = "Tags aplicadas aos recursos"
  type        = map(string)
  default     = {}
}
