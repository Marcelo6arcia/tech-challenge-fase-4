variable "aws_region" {
  description = "Região da AWS onde o bucket de state será criado"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Profile do AWS CLI usado localmente"
  type        = string
  default     = "fiap"
}

variable "state_bucket_prefix" {
  description = "Prefixo do nome do bucket de state (um sufixo aleatório é acrescentado para garantir unicidade global)"
  type        = string
  default     = "togglemaster-tfstate"
}
