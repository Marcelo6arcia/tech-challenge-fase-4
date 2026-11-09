# =============================================================================
# MÓDULO: gitops
# Camada de plataforma instalada no cluster pelo Terraform:
#   1. ingress-nginx        — porta de entrada HTTP (NLB)
#   2. External Secrets     — traz segredos do AWS Secrets Manager para o cluster
#   3. Argo CD              — motor de GitOps
#   4. AppProject + root app (padrão app-of-apps) apontando para o repo GitOps
#
# A partir daqui, TUDO o que roda no cluster é declarado no repositório GitOps.
# Ninguém mais precisa rodar `kubectl apply` da própria máquina.
# =============================================================================

resource "kubernetes_namespace" "app" {
  metadata {
    name = var.app_namespace

    labels = {
      "app.kubernetes.io/part-of"          = "togglemaster"
      "pod-security.kubernetes.io/enforce" = "baseline"
    }
  }
}

# -----------------------------------------------------------------------------
# 1. ingress-nginx
# -----------------------------------------------------------------------------
resource "helm_release" "ingress_nginx" {
  count = var.install_ingress_nginx ? 1 : 0

  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.ingress_nginx_chart_version
  namespace        = "ingress-nginx"
  create_namespace = true
  wait             = true
  timeout          = 900

  values = [yamlencode({
    controller = {
      replicaCount = 2
      service = {
        type = "LoadBalancer"
        annotations = {
          "service.beta.kubernetes.io/aws-load-balancer-type"            = "nlb"
          "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
          "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "instance"
        }
      }
      metrics = { enabled = true }
      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "500m", memory = "256Mi" }
      }
    }
  })]
}

# -----------------------------------------------------------------------------
# 2. External Secrets Operator
# -----------------------------------------------------------------------------
resource "helm_release" "external_secrets" {
  count = var.install_external_secrets ? 1 : 0

  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.external_secrets_chart_version
  namespace        = "external-secrets"
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [yamlencode({
    installCRDs = true
    serviceAccount = {
      create = true
      name   = var.external_secrets_service_account
      annotations = {
        "eks.amazonaws.com/role-arn" = var.external_secrets_role_arn
      }
    }
    resources = {
      requests = { cpu = "50m", memory = "96Mi" }
      limits   = { cpu = "200m", memory = "256Mi" }
    }
  })]
}

# -----------------------------------------------------------------------------
# 3. Argo CD
# -----------------------------------------------------------------------------
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = var.argocd_namespace
  create_namespace = true
  wait             = true
  timeout          = 900

  values = [yamlencode({
    global = {
      domain = var.argocd_hostname
    }
    configs = {
      params = {
        # TLS terminado no Ingress; o servidor responde em HTTP interno
        "server.insecure" = true
        # Intervalo de reconciliação (padrão 3m). 30s deixa a demo do vídeo fluida.
        "timeout.reconciliation" = "30s"
      }
      cm = {
        "application.resourceTrackingMethod" = "annotation"
        "kustomize.buildOptions"             = "--enable-helm"
      }
    }
    server = {
      replicas = 1
      ingress = {
        enabled          = var.argocd_ingress_enabled
        ingressClassName = "nginx"
        hostname         = var.argocd_hostname
        path             = "/"
        pathType         = "Prefix"
      }
      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
    }
    repoServer = {
      resources = {
        requests = { cpu = "100m", memory = "192Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
    }
    controller = {
      resources = {
        requests = { cpu = "150m", memory = "256Mi" }
        limits   = { cpu = "1000m", memory = "1Gi" }
      }
    }
    applicationSet = {
      enabled = true
    }
    notifications = {
      enabled = false
    }
    dex = {
      enabled = false
    }
  })]

  depends_on = [helm_release.ingress_nginx]
}

# -----------------------------------------------------------------------------
# Credencial do repositório GitOps (apenas se o repositório for privado)
# -----------------------------------------------------------------------------
resource "kubernetes_secret" "gitops_repo" {
  count = var.gitops_repo_private ? 1 : 0

  metadata {
    name      = "gitops-repo-credentials"
    namespace = var.argocd_namespace

    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type     = "git"
    url      = var.gitops_repo_url
    username = var.gitops_repo_username
    password = var.gitops_repo_token
  }

  depends_on = [helm_release.argocd]
}

# -----------------------------------------------------------------------------
# 4. AppProject + Application raiz (app-of-apps)
# -----------------------------------------------------------------------------
resource "helm_release" "argocd_apps" {
  name       = "argocd-apps"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version
  namespace  = var.argocd_namespace
  wait       = true

  values = [yamlencode({
    projects = {
      observability = {
        namespace   = var.argocd_namespace
        description = "Stack OTel, metricas, logs e resposta a incidentes da Fase 4"
        sourceRepos = [
          var.gitops_repo_url,
          "https://prometheus-community.github.io/helm-charts",
          "https://grafana.github.io/helm-charts",
          "https://open-telemetry.github.io/opentelemetry-helm-charts",
        ]
        destinations = [
          { namespace = "observability", server = "https://kubernetes.default.svc" },
          # Role/RoleBinding do responder limitada ao auth-service.
          { namespace = var.app_namespace, server = "https://kubernetes.default.svc" },
        ]
        clusterResourceWhitelist = [
          { group = "", kind = "Namespace" },
          { group = "storage.k8s.io", kind = "StorageClass" },
          { group = "rbac.authorization.k8s.io", kind = "ClusterRole" },
          { group = "rbac.authorization.k8s.io", kind = "ClusterRoleBinding" },
        ]
        namespaceResourceWhitelist = [
          { group = "", kind = "ConfigMap" },
          { group = "", kind = "Secret" },
          { group = "", kind = "Service" },
          { group = "", kind = "ServiceAccount" },
          { group = "", kind = "PersistentVolumeClaim" },
          { group = "", kind = "Pod" },
          { group = "apps", kind = "Deployment" },
          { group = "apps", kind = "DaemonSet" },
          { group = "apps", kind = "StatefulSet" },
          { group = "batch", kind = "Job" },
          { group = "policy", kind = "PodDisruptionBudget" },
          { group = "networking.k8s.io", kind = "NetworkPolicy" },
          { group = "rbac.authorization.k8s.io", kind = "Role" },
          { group = "rbac.authorization.k8s.io", kind = "RoleBinding" },
          { group = "external-secrets.io", kind = "SecretStore" },
          { group = "external-secrets.io", kind = "ExternalSecret" },
        ]
      }
      togglemaster = {
        namespace   = var.argocd_namespace
        description = "ToggleMaster - Tech Challenge Fase 4"
        sourceRepos = [var.gitops_repo_url]
        destinations = [
          { namespace = var.app_namespace, server = "https://kubernetes.default.svc" },
          { namespace = var.argocd_namespace, server = "https://kubernetes.default.svc" },
        ]
        clusterResourceWhitelist = [
          { group = "", kind = "Namespace" },
        ]
        namespaceResourceWhitelist = [
          { group = "*", kind = "*" },
        ]
      }
    }

    applications = {
      root = {
        namespace = var.argocd_namespace
        project   = "togglemaster"
        source = {
          repoURL        = var.gitops_repo_url
          targetRevision = var.gitops_repo_revision
          path           = var.gitops_root_path
          directory = {
            recurse = true
          }
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = var.argocd_namespace
        }
        syncPolicy = {
          automated = {
            prune      = true
            selfHeal   = true
            allowEmpty = false
          }
          syncOptions = ["CreateNamespace=true"]
        }
      }
    }
  })]

  depends_on = [
    helm_release.argocd,
    kubernetes_namespace.app,
  ]
}
