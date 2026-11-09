output "cluster_name" {
  value       = aws_eks_cluster.this.name
  description = "Nome do cluster EKS"
}

output "cluster_endpoint" {
  value       = aws_eks_cluster.this.endpoint
  description = "Endpoint da API do cluster"
}

output "cluster_certificate_authority_data" {
  value       = aws_eks_cluster.this.certificate_authority[0].data
  description = "CA do cluster (base64)"
}

output "cluster_version" {
  value       = aws_eks_cluster.this.version
  description = "Versão do Kubernetes"
}

output "cluster_security_group_id" {
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  description = "Security Group criado pelo EKS e compartilhado entre control plane e nós"
}

output "oidc_provider_arn" {
  value       = try(aws_iam_openid_connect_provider.this[0].arn, null)
  description = "ARN do OIDC provider (usado pelo módulo irsa)"
}

output "oidc_provider_url" {
  value       = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
  description = "URL do issuer OIDC sem o esquema"
}

output "node_role_arn" {
  value       = local.node_role_arn
  description = "ARN da role dos worker nodes"
}

output "node_group_name" {
  value       = aws_eks_node_group.this.node_group_name
  description = "Nome do Managed Node Group"
}
