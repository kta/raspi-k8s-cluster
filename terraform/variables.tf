# Proxmox API 接続情報
variable "proxmox_api_url" {
  description = "Proxmox API エンドポイント URL"
  type        = string
  default     = "https://192.168.100.101:8006/"
}

variable "proxmox_api_token_id" {
  description = "Proxmox API トークン ID (環境変数 PM_API_TOKEN_ID から取得)"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API トークンシークレット (環境変数 PM_API_TOKEN_SECRET から取得)"
  type        = string
  sensitive   = true
}

# 物理ノード設定
variable "proxmox_nodes" {
  description = "Proxmox 物理ノード名のリスト"
  type        = list(string)
  default     = ["pi-node-1", "pi-node-2", "pi-node-3"]
}

# ストレージ設定
variable "proxmox_storage" {
  description = "Ceph ストレージプール名"
  type        = string
  default     = "ceph-vm"
}

# ネットワーク設定
variable "network_gateway" {
  description = "ネットワークゲートウェイ"
  type        = string
  default     = "192.168.100.1"
}

variable "network_dns" {
  description = "DNS サーバー"
  type        = string
  default     = "192.168.100.1"
}

variable "network_subnet" {
  description = "ネットワークサブネット (CIDR)"
  type        = string
  default     = "24"
}

variable "kube_vip" {
  description = "kube-vip 仮想 IP アドレス"
  type        = string
  default     = "192.168.100.200"
}

# Control Plane 設定
variable "control_plane_ips" {
  description = "Control Plane VM の IP アドレスリスト"
  type        = list(string)
  default     = ["192.168.100.201", "192.168.100.202", "192.168.100.203"]
}

variable "control_plane_hostnames" {
  description = "Control Plane VM のホスト名リスト"
  type        = list(string)
  default     = ["pve-vm-cp-1", "pve-vm-cp-2", "pve-vm-cp-3"]
}

# Worker 設定
variable "worker_ips" {
  description = "Worker VM の IP アドレスリスト"
  type        = list(string)
  default     = ["192.168.100.211", "192.168.100.212", "192.168.100.213"]
}

variable "worker_hostnames" {
  description = "Worker VM のホスト名リスト"
  type        = list(string)
  default     = ["pve-vm-wk-1", "pve-vm-wk-2", "pve-vm-wk-3"]
}

# VM リソース設定
variable "vm_cpu_cores" {
  description = "各 VM の CPU コア数"
  type        = number
  default     = 2
}

variable "vm_memory_mb" {
  description = "各 VM のメモリ容量 (MB)"
  type        = number
  default     = 2048
}

variable "vm_disk_size_gb" {
  description = "各 VM のディスクサイズ (GB)"
  type        = number
  default     = 20
}

# Kubernetes 設定
variable "kubernetes_version" {
  description = "Kubernetes バージョン"
  type        = string
  default     = "1.35"
}

variable "kubernetes_pod_network_cidr" {
  description = "Kubernetes Pod ネットワーク CIDR"
  type        = string
  default     = "10.244.0.0/16"
}

# SSH 設定
variable "github_username" {
  description = "GitHub ユーザー名 (SSH 公開鍵取得用)"
  type        = string
}

# タイムゾーン設定
variable "timezone" {
  description = "VM のタイムゾーン"
  type        = string
  default     = "Asia/Tokyo"
}

# SSH 秘密鍵パス
variable "ssh_private_key_path" {
  description = "SSH 秘密鍵のパス"
  type        = string
  default     = "~/.ssh/id_rsa"
}

# ネットワークインターフェース名
variable "network_interface" {
  description = "VM のネットワークインターフェース名 (kube-vip 用)"
  type        = string
  default     = "eth0"
}
