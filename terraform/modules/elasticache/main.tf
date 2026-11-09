# =============================================================================
# MÓDULO: elasticache
# Cluster Redis usado como cache de avaliação de flags pelo evaluation-service.
# =============================================================================

resource "aws_security_group" "this" {
  name        = "${var.name}-redis-sg"
  description = "Acesso Redis ao cluster ${var.name}"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-redis-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "from_sg" {
  for_each = var.allowed_security_groups

  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = each.value
  from_port                    = var.port
  to_port                      = var.port
  ip_protocol                  = "tcp"
  description                  = "Redis a partir de ${each.key}"
}

resource "aws_vpc_security_group_egress_rule" "vpc_only" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "-1"
  description       = "Saida restrita a VPC"
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.name}-redis-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, { Name = "${var.name}-redis-subnet-group" })
}

resource "aws_elasticache_cluster" "this" {
  cluster_id           = "${var.name}-redis"
  engine               = "redis"
  engine_version       = var.engine_version
  node_type            = var.node_type
  num_cache_nodes      = 1
  parameter_group_name = var.parameter_group_name
  port                 = var.port

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.this.id]

  snapshot_retention_limit = var.snapshot_retention_limit
  apply_immediately        = true

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "engine-log"
  }

  tags = merge(var.tags, {
    Name    = "${var.name}-redis"
    Service = "evaluation-service"
  })
}

resource "aws_cloudwatch_log_group" "redis" {
  name              = "/aws/elasticache/${var.name}"
  retention_in_days = 7

  tags = var.tags
}
