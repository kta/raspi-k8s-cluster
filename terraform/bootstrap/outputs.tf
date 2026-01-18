output "argocd_namespace" {
  value       = kubernetes_namespace.argocd.metadata[0].name
  description = "ArgoCD がインストールされた Namespace"
}

output "argocd_server_service" {
  value       = "argocd-server"
  description = "ArgoCD Server の Service 名"
}

output "argocd_initial_admin_password_command" {
  value       = "kubectl -n ${var.argocd_namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
  description = "ArgoCD 初期管理者パスワード取得コマンド"
}

output "argocd_port_forward_command" {
  value       = "kubectl port-forward svc/argocd-server -n ${var.argocd_namespace} 8080:443"
  description = "ArgoCD UI へのポートフォワードコマンド"
}

output "argocd_nodeport_url" {
  value       = "https://<NODE_IP>:30443"
  description = "NodePort 経由での ArgoCD UI アクセス URL"
}