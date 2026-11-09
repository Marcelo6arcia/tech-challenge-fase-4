variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
}

variable "kubernetes_version" {
  description = "Versão do Kubernetes do control plane. null deixa o EKS usar a versão padrão dele."
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Subnets do control plane (mínimo 2 AZs)"
  type        = list(string)
}

variable "node_subnet_ids" {
  description = "Subnets onde os worker nodes serão criados"
  type        = list(string)
}

variable "public_access_cidrs" {
  description = "CIDRs autorizados a acessar o endpoint público da API do cluster."
  type        = list(string)

  # Sem default aberto de proposito. O default ["0.0.0.0/0"] anterior deixava o
  # endpoint da API exposto a internet inteira em qualquer uso do modulo, e o
  # trivy config apontava isso como AVD-AWS-0041 (CRITICAL), travando o pipeline
  # de IaC. Quem chama o modulo passa a ser obrigado a declarar de onde o
  # cluster pode ser alcancado.
  default = []

  validation {
    condition     = length(var.public_access_cidrs) > 0
    error_message = "Informe ao menos um CIDR em public_access_cidrs. Uma lista vazia faz o EKS aplicar 0.0.0.0/0 silenciosamente."
  }
}

variable "enabled_cluster_log_types" {
  description = "Tipos de log do control plane enviados ao CloudWatch"
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "cluster_log_retention_days" {
  description = "Retenção dos logs do control plane"
  type        = number
  default     = 7
}

# --- IAM ---------------------------------------------------------------------
variable "create_iam_roles" {
  description = "true = cria as roles (conta pessoal). false = usa ARNs existentes, ex.: LabRole do AWS Academy."
  type        = bool
  default     = true
}

variable "cluster_role_arn" {
  description = "ARN da role do control plane quando create_iam_roles = false"
  type        = string
  default     = null
}

variable "node_role_arn" {
  description = "ARN da role dos nós quando create_iam_roles = false"
  type        = string
  default     = null
}

variable "create_oidc_provider" {
  description = "Cria o OIDC provider do cluster (base do IRSA). Deixe false no AWS Academy."
  type        = bool
  default     = true
}

variable "cluster_admin_principal_arns" {
  description = "ARNs de usuários/roles IAM que recebem acesso administrativo ao cluster"
  type        = list(string)
  default     = []
}

# --- Node Group --------------------------------------------------------------
variable "node_instance_types" {
  description = "Tipos de instância do Managed Node Group"
  type        = list(string)
  default     = ["t3a.medium"]
}

variable "node_ami_type" {
  description = "Tipo de AMI (AL2023_x86_64_STANDARD ou AL2023_ARM_64_STANDARD)"
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "node_capacity_type" {
  description = "ON_DEMAND ou SPOT"
  type        = string
  default     = "ON_DEMAND"
}

variable "node_disk_size" {
  description = "Tamanho do disco EBS dos nós, em GB"
  type        = number
  default     = 30
}

variable "node_min_size" {
  description = "Mínimo de nós"
  type        = number
  default     = 2
}

variable "node_desired_size" {
  description = "Quantidade desejada de nós"
  type        = number
  default     = 3
}

variable "node_max_size" {
  description = "Máximo de nós"
  type        = number
  default     = 5
}

variable "cluster_addons" {
  description = "Add-ons gerenciados do EKS"
  type        = list(string)
  default     = ["vpc-cni", "coredns", "kube-proxy", "metrics-server"]
}

variable "tags" {
  description = "Tags aplicadas aos recursos do módulo"
  type        = map(string)
  default     = {}
}
