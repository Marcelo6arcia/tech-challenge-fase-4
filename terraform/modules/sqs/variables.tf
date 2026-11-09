variable "queue_name" {
  description = "Nome da fila principal"
  type        = string
}

variable "message_retention_seconds" {
  description = "Retenção de mensagens na fila principal"
  type        = number
  default     = 86400
}

variable "visibility_timeout_seconds" {
  description = "Visibility timeout"
  type        = number
  default     = 30
}

variable "receive_wait_time_seconds" {
  description = "Long polling (0 a 20)"
  type        = number
  default     = 20
}

variable "enable_dlq" {
  description = "Cria uma Dead Letter Queue"
  type        = bool
  default     = true
}

variable "max_receive_count" {
  description = "Tentativas antes de mover a mensagem para a DLQ"
  type        = number
  default     = 5
}

variable "dlq_retention_seconds" {
  description = "Retenção de mensagens na DLQ"
  type        = number
  default     = 1209600
}

variable "tags" {
  description = "Tags aplicadas aos recursos"
  type        = map(string)
  default     = {}
}
