variable "identifier" {
  description = "Identificador da instância RDS"
  type        = string
}

variable "service" {
  description = "Microsserviço dono deste banco (usado em tags e no nome do secret)"
  type        = string
}

variable "db_name" {
  description = "Nome do banco de dados inicial"
  type        = string
}

variable "username" {
  description = "Usuário master"
  type        = string
}

variable "vpc_id" {
  description = "VPC onde o security group será criado"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR da VPC (usado na regra de egress)"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets privadas do subnet group (quando create_subnet_group = true)"
  type        = list(string)
  default     = []
}

variable "create_subnet_group" {
  description = "Cria um subnet group próprio. Use false para compartilhar um subnet group existente."
  type        = bool
  default     = false
}

variable "db_subnet_group_name" {
  description = "Subnet group existente (quando create_subnet_group = false)"
  type        = string
  default     = null
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

variable "engine_version" {
  description = "Versão do PostgreSQL"
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "Classe da instância"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Armazenamento inicial em GB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Teto do autoscaling de storage em GB"
  type        = number
  default     = 50
}

variable "multi_az" {
  description = "Alta disponibilidade entre AZs (dobra o custo)"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Dias de retenção de backup automático"
  type        = number
  default     = 1
}

variable "deletion_protection" {
  description = "Impede exclusão acidental da instância"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Pula o snapshot final no destroy (true em ambiente de estudo)"
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "Aplica alterações imediatamente em vez de na janela de manutenção"
  type        = bool
  default     = true
}

variable "performance_insights_enabled" {
  description = "Habilita o Performance Insights"
  type        = bool
  default     = false
}

variable "secret_name_prefix" {
  description = "Prefixo do nome do secret no Secrets Manager"
  type        = string
  default     = "togglemaster/dev"
}

variable "secret_recovery_window_days" {
  description = "Janela de recuperação do secret. 0 apaga na hora — conveniente em laboratório onde se recria o ambiente."
  type        = number
  default     = 0
}

variable "tags" {
  description = "Tags aplicadas aos recursos do módulo"
  type        = map(string)
  default     = {}
}
