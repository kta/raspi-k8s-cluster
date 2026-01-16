output "control_plane_ips" {
  description = "Control Plane VM の IP アドレス一覧"
  value = {
    for idx, hostname in var.control_plane_hostnames :
    hostname => var.control_plane_ips[idx]
  }
}

output "worker_ips" {
  description = "Worker VM の IP アドレス一覧"
  value = {
    for idx, hostname in var.worker_hostnames :
    hostname => var.worker_ips[idx]
  }
}

output "kube_vip_address" {
  description = "kube-vip 仮想 IP アドレス"
  value       = var.kube_vip
}

output "kubernetes_api_endpoint" {
  description = "Kubernetes API Server エンドポイント"
  value       = "https://${var.kube_vip}:6443"
}

output "kubeconfig_path" {
  description = "kubeconfig ファイルパス"
  value       = module.kubernetes.kubeconfig_path
}

output "argocd_password" {
  description = "ArgoCD 初期管理者パスワード"
  value       = module.argocd.argocd_admin_password
  sensitive   = true
}

output "argocd_access_command" {
  description = "ArgoCD UI アクセスコマンド"
  value       = module.argocd.access_command
}

output "next_steps" {
  description = "次のステップ"
  value       = <<-EOT

  ✅ Terraform apply が完了しました！

  次のステップ:

  1. kubeconfig を設定:
     export KUBECONFIG=${module.kubernetes.kubeconfig_path}

  2. クラスターの状態を確認:
     kubectl get nodes
     kubectl get pods -A

  3. ArgoCD にアクセス:
     ${module.argocd.access_command}
     ブラウザで https://localhost:8080 にアクセス
     ユーザー名: admin
     パスワード: terraform output -raw argocd_password

  4. 高可用性テスト:
     Proxmox UI で任意の物理ノードを停止して動作確認

  EOT
}
