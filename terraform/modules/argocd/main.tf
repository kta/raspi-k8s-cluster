resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace

    labels = merge(
      {
        "app.kubernetes.io/name"       = "argocd"
        "app.kubernetes.io/managed-by" = "terraform"
      },
      var.labels
    )
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations,
      metadata[0].labels["kubernetes.io/metadata.name"]
    ]
  }
}

resource "kubernetes_config_map_v1" "environment_config" {
  metadata {
    name      = "environment-config"
    namespace = kubernetes_namespace_v1.this.metadata[0].name

    labels = {
      "app.kubernetes.io/name"       = "argocd"
      "app.kubernetes.io/component"  = "config"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    environment      = var.environment
    metallb_ip_range = var.metallb_ip_range
    ingress_ip       = var.ingress_ip
    vip              = var.vip
  }
}

resource "helm_release" "this" {
  name       = var.release_name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version
  namespace  = kubernetes_namespace_v1.this.metadata[0].name

  values = [
    templatefile("${path.module}/values.yaml.tpl", {
      enable_ha = var.enable_ha
    })
  ]

  wait             = true
  timeout          = var.timeout
  create_namespace = false

  depends_on = [kubernetes_namespace_v1.this]
}
