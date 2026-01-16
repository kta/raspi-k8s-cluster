provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = true

  ssh {
    agent = true
  }
}

# Helm/Kubernetes プロバイダーは kubeconfig ファイルベースで設定
# Kubernetes ブートストラップ後に有効になる
provider "helm" {
  kubernetes {
    config_path = "${path.module}/modules/kubernetes/kubeconfig.yaml"
  }
}

provider "kubernetes" {
  config_path = "${path.module}/modules/kubernetes/kubeconfig.yaml"
}
