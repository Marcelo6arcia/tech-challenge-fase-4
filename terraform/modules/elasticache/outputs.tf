output "endpoint" {
  value       = aws_elasticache_cluster.this.cache_nodes[0].address
  description = "Endpoint do nó Redis"
}

output "port" {
  value       = aws_elasticache_cluster.this.cache_nodes[0].port
  description = "Porta do Redis"
}

output "redis_url" {
  value       = "redis://${aws_elasticache_cluster.this.cache_nodes[0].address}:${aws_elasticache_cluster.this.cache_nodes[0].port}"
  description = "URL de conexão consumida pelo evaluation-service"
}

output "security_group_id" {
  value       = aws_security_group.this.id
  description = "Security group do Redis"
}
