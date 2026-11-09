variable "name" {
  description = "Prefixo de nome do cluster"
  type        = string
}

variable "vpc_id" {
  description = "VPC do security group"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR da VPC (regra de egress)"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets privadas do subnet group"
  type        = list(string)
}

variable "allowed_security_groups" {
  description = <<-EOT
    Security groups autorizados a conectar, como mapa {rótulo => id}.

    Mapa e não lista de propósito: o id do security group do EKS só existe
    depois do apply, e `for_each` sobre um conjunto com valores desconhecidos
    falha no plan ("Invalid for_each argument"). Com mapa, a CHAVE é estática e
    só o valor é resolvido em tempo de apply.
  EOT
  type        = map(string)
  default     = {}
}

variable "node_type" {
  description = "Tipo do nó de cache"
  type        = string
  default     = "cache.t3.micro"
}

variable "engine_version" {
  description = "Versão do Redis"
  type        = string
  default     = "7.1"
}

variable "parameter_group_name" {
  description = "Parameter group"
  type        = string
  default     = "default.redis7"
}

variable "port" {
  description = "Porta do Redis"
  type        = number
  default     = 6379
}

variable "snapshot_retention_limit" {
  description = "Dias de retenção de snapshot"
  type        = number
  default     = 0
}

variable "tags" {
  description = "Tags aplicadas aos recursos"
  type        = map(string)
  default     = {}
}
