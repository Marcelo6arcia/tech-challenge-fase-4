# =============================================================================
# MÓDULO: eks
# Cluster EKS, Managed Node Group, provider OIDC (para IRSA), add-ons e
# controle de acesso via EKS Access Entries.
# =============================================================================
#
# COMPATIBILIDADE AWS ACADEMY (Opção A do enunciado)
# --------------------------------------------------
# Este módulo cria as roles de IAM por padrão (Opção B — conta pessoal).
# Para rodar no AWS Academy basta definir:
#   create_iam_roles     = false
#   cluster_role_arn     = data.aws_iam_role.lab_role.arn
#   node_role_arn        = data.aws_iam_role.lab_role.arn
# Nenhum recurso aws_iam_* é criado quando create_iam_roles = false.
# =============================================================================

locals {
  create_roles     = var.create_iam_roles
  cluster_role_arn = local.create_roles ? aws_iam_role.cluster[0].arn : var.cluster_role_arn
  node_role_arn    = local.create_roles ? aws_iam_role.node[0].arn : var.node_role_arn
}

# -----------------------------------------------------------------------------
# IAM — Control Plane
# -----------------------------------------------------------------------------
resource "aws_iam_role" "cluster" {
  count = local.create_roles ? 1 : 0
  name  = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  count      = local.create_roles ? 1 : 0
  role       = aws_iam_role.cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# -----------------------------------------------------------------------------
# IAM — Worker Nodes
# -----------------------------------------------------------------------------
# ATENÇÃO: diferente da Fase 2, a role dos nós NÃO recebe SQSFullAccess nem
# DynamoDBFullAccess. Cada aplicação recebe sua própria role via IRSA
# (módulo terraform/modules/irsa), respeitando o princípio do menor privilégio.
resource "aws_iam_role" "node" {
  count = local.create_roles ? 1 : 0
  name  = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_managed" {
  for_each = local.create_roles ? toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]) : toset([])

  role       = aws_iam_role.node[0].name
  policy_arn = each.value
}

# -----------------------------------------------------------------------------
# Cluster
# -----------------------------------------------------------------------------
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = local.cluster_role_arn

  # API_AND_CONFIG_MAP permite gerenciar acesso via Access Entries (recomendado)
  # sem quebrar o aws-auth ConfigMap eventualmente criado por ferramentas legadas.
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  # O trivy ancora o AVD-AWS-0041 neste bloco. Ele resolve public_access_cidrs
  # estaticamente e, sem um literal no codigo, assume o default da AWS —
  # 0.0.0.0/0. O valor real nao pode ser versionado: e o IP de quem opera, ele
  # muda, e este repositorio e publico. Ele chega por TF_VAR_public_access_cidrs.
  #
  # O cenario que o trivy supoe nao pode ocorrer: a validation em variables.tf
  # reprova o plan quando a lista vem vazia, entao nao existe caminho em que
  # este modulo aplique 0.0.0.0/0 por omissao. Confira ali.
  # trivy:ignore:AVD-AWS-0041
  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true

    # Risco aceito e registrado em docs/ARQUITETURA.md. Fechar o endpoint
    # publico exige alcancar a API por dentro da VPC, e a VPC deste ambiente
    # roda sem NAT Gateway por decisao de custo (~US$ 65/mes em duas AZs, um
    # quarto do total). Sem NAT, operar o cluster exigiria bastion ou VPN, que
    # custam mais do que o proprio ambiente que estao protegendo. A postura de
    # producao e enable_nat_gateway = true com endpoint_public_access = false.
    # A exposicao fica limitada por public_access_cidrs e pelo endpoint privado
    # seguir habilitado.
    # trivy:ignore:AVD-AWS-0040
    endpoint_public_access = true

    public_access_cidrs = var.public_access_cidrs
  }

  enabled_cluster_log_types = var.enabled_cluster_log_types

  tags = merge(var.tags, { Name = var.cluster_name })

  # O log group tem que existir ANTES do cluster. Se o EKS chegar primeiro, ele
  # cria /aws/eks/<cluster>/cluster sozinho — com retenção "Never expire" — e o
  # apply quebra com ResourceAlreadyExistsException. Criando na ordem certa, a
  # retenção é a nossa (var.cluster_log_retention_days) e o log não acumula
  # indefinidamente. É corrida, então na primeira vez pode passar despercebido.
  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_cloudwatch_log_group.cluster,
  ]
}

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.cluster_log_retention_days

  tags = var.tags
}

# -----------------------------------------------------------------------------
# OIDC — base do IRSA (IAM Roles for Service Accounts)
# -----------------------------------------------------------------------------
data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  count = var.create_oidc_provider ? 1 : 0

  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]

  tags = merge(var.tags, { Name = "${var.cluster_name}-oidc" })
}

# -----------------------------------------------------------------------------
# Launch Template dos nós
# -----------------------------------------------------------------------------
# http_put_response_hop_limit = 2: sem isso, um pod (que está a 1 hop extra do
# host) não alcança o IMDS. Necessário para o AWS SDK resolver credenciais.
# http_tokens = required força IMDSv2 (mitiga SSRF -> roubo de credencial).
resource "aws_launch_template" "node" {
  name_prefix = "${var.cluster_name}-node-"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.node_disk_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.cluster_name}-node" })
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Managed Node Group
# -----------------------------------------------------------------------------
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-ng"
  node_role_arn   = local.node_role_arn
  subnet_ids      = var.node_subnet_ids

  instance_types = var.node_instance_types
  ami_type       = var.node_ami_type
  capacity_type  = var.node_capacity_type

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  scaling_config {
    min_size     = var.node_min_size
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    workload = "togglemaster"
  }

  tags = merge(var.tags, { Name = "${var.cluster_name}-ng" })

  # Ignora desired_size para não brigar com o Cluster Autoscaler/HPA
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [aws_iam_role_policy_attachment.node_managed]
}

# -----------------------------------------------------------------------------
# Add-ons gerenciados
# -----------------------------------------------------------------------------
resource "aws_eks_addon" "this" {
  for_each = toset(var.cluster_addons)

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.value
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags

  depends_on = [aws_eks_node_group.this]
}

# -----------------------------------------------------------------------------
# Access Entries — acesso administrativo adicional ao cluster
# -----------------------------------------------------------------------------
resource "aws_eks_access_entry" "admins" {
  for_each = toset(var.cluster_admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"

  tags = var.tags
}

resource "aws_eks_access_policy_association" "admins" {
  for_each = toset(var.cluster_admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admins]
}
