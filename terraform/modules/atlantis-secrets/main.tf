resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace

    labels = merge(
      {
        "app.kubernetes.io/name"       = "atlantis"
        "app.kubernetes.io/managed-by" = "terraform"
      },
      var.labels
    )
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations
    ]
  }
}

resource "kubernetes_secret_v1" "github" {
  metadata {
    name      = var.secret_name
    namespace = kubernetes_namespace_v1.this.metadata[0].name

    labels = merge(
      {
        "app.kubernetes.io/name"       = "atlantis"
        "app.kubernetes.io/component"  = "credentials"
        "app.kubernetes.io/managed-by" = "terraform"
      },
      var.labels
    )
  }

  data = {
    token = var.github_token
  }

  type = "Opaque"
}
