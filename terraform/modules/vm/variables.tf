variable "vm_id" {
  description = "VM ID"
  type        = number
}

variable "vm_name" {
  description = "VM 名"
  type        = string
}

variable "node_name" {
  description = "配置先の Proxmox ノード名"
  type        = string
}

variable "ip_address" {
  description = "VM の IP アドレス"
  type        = string
}

variable "gateway" {
  description = "ゲートウェイ"
  type        = string
}

variable "dns" {
  description = "DNS サーバー"
  type        = string
}

variable "subnet" {
  description = "サブネットマスク (CIDR)"
  type        = string
}

variable "cpu_cores" {
  description = "CPU コア数"
  type        = number
}

variable "memory_mb" {
  description = "メモリ容量 (MB)"
  type        = number
}

variable "disk_size_gb" {
  description = "ディスクサイズ (GB)"
  type        = number
}

variable "storage_pool" {
  description = "ストレージプール名"
  type        = string
}

variable "cloud_init_user_data" {
  description = "Cloud-Init user-data 設定"
  type        = string
}

variable "cloud_image_file_id" {
  description = "Cloud Image ファイル ID"
  type        = string
}
