# =============================================================================
# MÓDULO: rds
# Uma instância RDS PostgreSQL com senha gerada automaticamente e publicada no
# AWS Secrets Manager. Reutilizável — o env dev instancia o módulo 3 vezes
# (auth, flag, targeting).
# =============================================================================
#
# Resolve a dor citada no enunciado ("credenciais em arquivos de texto sem
# segurança"): nenhuma senha aparece em .tfvars, em manifesto YAML ou no
# repositório. O Terraform gera, guarda no Secrets Manager e o External Secrets
# Operator materializa o Secret dentro do cluster em tempo de execução.
# =============================================================================

resource "random_password" "master" {
  length  = 24
  special = true
  # Caracteres proibidos pelo RDS na senha master
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_security_group" "this" {
  name        = "${var.identifier}-sg"
  description = "Acesso PostgreSQL a instancia ${var.identifier}"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.identifier}-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "from_sg" {
  for_each = var.allowed_security_groups

  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = each.value
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL a partir de ${each.key}"
}

# Egress restrito: o banco não inicia conexões para a internet
resource "aws_vpc_security_group_egress_rule" "vpc_only" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "-1"
  description       = "Saida restrita a VPC"
}

resource "aws_db_subnet_group" "this" {
  count = var.create_subnet_group ? 1 : 0

  name       = "${var.identifier}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, { Name = "${var.identifier}-subnet-group" })
}

resource "aws_db_instance" "this" {
  identifier = var.identifier

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.username
  password = random_password.master.result
  port     = 5432

  db_subnet_group_name   = var.create_subnet_group ? aws_db_subnet_group.this[0].name : var.db_subnet_group_name
  vpc_security_group_ids = [aws_security_group.this.id]
  publicly_accessible    = false
  multi_az               = var.multi_az

  backup_retention_period = var.backup_retention_period
  copy_tags_to_snapshot   = true
  deletion_protection     = var.deletion_protection
  skip_final_snapshot     = var.skip_final_snapshot

  auto_minor_version_upgrade = true
  apply_immediately          = var.apply_immediately

  performance_insights_enabled    = var.performance_insights_enabled
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = merge(var.tags, {
    Name    = var.identifier
    Service = var.service
  })
}

# -----------------------------------------------------------------------------
# Secrets Manager — credencial consumida pelo External Secrets Operator
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.secret_name_prefix}/${var.service}/database"
  description             = "Credenciais do RDS ${var.identifier} (${var.service})"
  recovery_window_in_days = var.secret_recovery_window_days

  tags = merge(var.tags, { Service = var.service })
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    username     = var.username
    password     = random_password.master.result
    host         = aws_db_instance.this.address
    port         = tostring(aws_db_instance.this.port)
    dbname       = var.db_name
    DATABASE_URL = "postgresql://${var.username}:${urlencode(random_password.master.result)}@${aws_db_instance.this.address}:${aws_db_instance.this.port}/${var.db_name}"
  })
}
