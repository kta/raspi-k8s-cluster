resource "helm_release" "this" {
  name       = var.release_name
  repository = "https://bitnami-labs.github.io/sealed-secrets"
  chart      = "sealed-secrets"
  version    = var.chart_version
  namespace  = var.namespace

  values = [
    yamlencode({
      fullnameOverride = var.fullname_override

      resources = {
        requests = {
          cpu    = var.resources.requests.cpu
          memory = var.resources.requests.memory
        }
        limits = {
          cpu    = var.resources.limits.cpu
          memory = var.resources.limits.memory
        }
      }

      nodeSelector = var.node_selector
      tolerations  = var.tolerations
    })
  ]

  wait             = true
  timeout          = var.timeout
  create_namespace = false
}
