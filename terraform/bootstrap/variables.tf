variable "kubeconfig_path" {
  type        = string
  default     = "~/.kube/config"
  description = "kubeconfig ファイルのパス"
}

variable "argocd_namespace" {
  type        = string
  default     = "argocd"
  description = "ArgoCD をインストールする Namespace"
}

variable "argocd_chart_version" {
  type        = string
  default     = "9.3.3" # 9.3.4にアップデート可能だが、現時点で9.3.3を使用
  description = "ArgoCD Helm Chart のバージョン"
}

variable "github_token" {
  type        = string
  sensitive   = true
  description = "GitHub Personal Access Token"
}

variable "github_username" {
  type        = string
  description = "GitHub ユーザー名"
}

variable "github_repo_url" {
  type        = string
  description = "GitOps リポジトリの URL（例: https://github.com/user/repo.git）"
}

variable "environment" {
  type        = string
  default     = "production"
  description = "デプロイ環境 (production または vagrant)"
  validation {
    condition     = contains(["production", "vagrant"], var.environment)
    error_message = "environment は production または vagrant である必要があります"
  }
}

variable "metallb_ip_range" {
  type        = string
  description = "MetalLB の IP アドレスプール範囲（例: 192.168.1.200-192.168.1.220）"
}

variable "ingress_ip" {
  type        = string
  description = "Ingress のデフォルト LoadBalancer IP"
}

variable "vip" {
  type        = string
  description = "Keepalived 仮想 IP アドレス"
}