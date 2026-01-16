output "kubeconfig_path" {
  description = "kubeconfig ファイルパス"
  value       = "${path.module}/kubeconfig.yaml"
}

output "cluster_endpoint" {
  description = "Kubernetes API Server エンドポイント"
  value       = "https://${var.kube_vip}:6443"
}
