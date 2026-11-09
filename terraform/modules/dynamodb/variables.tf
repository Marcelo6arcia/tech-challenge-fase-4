variable "table_name" {
  description = "Nome da tabela DynamoDB"
  type        = string
  default     = "ToggleMasterAnalytics"
}

variable "billing_mode" {
  description = "PAY_PER_REQUEST (on-demand) ou PROVISIONED"
  type        = string
  default     = "PAY_PER_REQUEST"
}

variable "point_in_time_recovery" {
  description = "Habilita PITR"
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Impede exclusão acidental da tabela"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags aplicadas aos recursos"
  type        = map(string)
  default     = {}
}
