output "argocd_namespace" {
  description = "ArgoCD Namespace"
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "argocd_admin_password" {
  description = "ArgoCD 初期管理者パスワード"
  value       = data.kubernetes_secret.argocd_initial_admin_secret.data["password"]
  sensitive   = true
}

output "argocd_server_service" {
  description = "ArgoCD Server Service 名"
  value       = "argocd-server"
}

output "access_command" {
  description = "ArgoCD UI アクセスコマンド"
  value       = "kubectl port-forward svc/argocd-server -n ${var.argocd_namespace} 8080:443"
}
