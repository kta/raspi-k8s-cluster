resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.argocd_namespace

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

# 環境設定用 ConfigMap
resource "kubernetes_config_map" "environment_config" {
  metadata {
    name      = "environment-config"
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }

  data = {
    environment      = var.environment
    metallb_ip_range = var.metallb_ip_range
    ingress_ip       = var.ingress_ip
    vip              = var.vip
  }

  depends_on = [kubernetes_namespace.argocd]
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  # Raspberry Pi 向けに最適化された values.yaml を使用
  values = [
    file("${path.module}/../../docs/argocd/values.yaml")
  ]

  # インストール完了まで待機
  wait    = true
  timeout = 900

  depends_on = [kubernetes_namespace.argocd]
}