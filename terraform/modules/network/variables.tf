variable "name_prefix" {
  description = "Prefixo aplicado ao nome de todos os recursos"
  type        = string
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Quantidade de Availability Zones (mínimo 2 — exigência do EKS e do subnet group do RDS)"
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2
    error_message = "O EKS e o RDS exigem ao menos 2 Availability Zones."
  }
}

variable "enable_nat_gateway" {
  description = "Cria NAT Gateway por AZ. Desligado por padrão para conter custo em ambiente de estudo."
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Habilita VPC Flow Logs no CloudWatch"
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "Retenção dos VPC Flow Logs em dias"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Tags aplicadas aos recursos do módulo"
  type        = map(string)
  default     = {}
}
