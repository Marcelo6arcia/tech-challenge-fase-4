output "argocd_initial_password_command" {
  value       = module.gitops.argocd_initial_password_command
  description = "Como obter a senha inicial do admin do Argo CD"
}

output "argocd_port_forward_command" {
  value       = module.gitops.argocd_port_forward_command
  description = "Como abrir a UI do Argo CD sem Ingress"
}

output "ingress_hostname_command" {
  value       = "kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
  description = "Hostname público do Network Load Balancer do Ingress"
}
