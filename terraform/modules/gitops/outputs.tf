output "argocd_namespace" {
  value       = var.argocd_namespace
  description = "Namespace do Argo CD"
}

output "app_namespace" {
  value       = kubernetes_namespace.app.metadata[0].name
  description = "Namespace das aplicações"
}

output "argocd_initial_password_command" {
  value       = "kubectl -n ${var.argocd_namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
  description = "Comando para recuperar a senha inicial do usuário admin do Argo CD"
}

output "argocd_port_forward_command" {
  value       = "kubectl -n ${var.argocd_namespace} port-forward svc/argocd-server 8080:80"
  description = "Acesso à UI do Argo CD sem Ingress"
}
