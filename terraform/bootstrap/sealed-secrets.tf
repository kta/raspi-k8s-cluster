resource "helm_release" "sealed_secrets" {
  name       = "sealed-secrets"
  repository = "https://bitnami-labs.github.io/sealed-secrets"
  chart      = "sealed-secrets"
  version    = "2.16.3"
  namespace  = "kube-system"

  values = [
    yamlencode({
      # Raspberry Pi 向けリソース制限
      resources = {
        requests = {
          cpu    = "50m"
          memory = "64Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "128Mi"
        }
      }
    })
  ]

  wait    = true
  timeout = 300
}

output "sealed_secrets_controller_name" {
  value       = helm_release.sealed_secrets.name
  description = "Sealed Secrets Controller リリース名"
}