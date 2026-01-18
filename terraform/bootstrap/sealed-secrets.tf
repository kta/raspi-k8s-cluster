resource "helm_release" "sealed_secrets" {
  name       = "sealed-secrets"
  repository = "https://bitnami-labs.github.io/sealed-secrets"
  chart      = "sealed-secrets"
  # version  = "..."  ← 削除します（自動で最新版が適用されます）
  namespace  = "kube-system"

  values = [
    yamlencode({
    #   # これを設定するとサービス名が確実に "sealed-secrets-controller" になります
    #   fullnameOverride = "sealed-secrets-controller"

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