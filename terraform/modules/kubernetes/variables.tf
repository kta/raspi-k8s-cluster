variable "control_plane_ips" {
  description = "Control Plane IP アドレスリスト"
  type        = list(string)
}

variable "control_plane_hostnames" {
  description = "Control Plane ホスト名リスト"
  type        = list(string)
}

variable "worker_ips" {
  description = "Worker IP アドレスリスト"
  type        = list(string)
}

variable "worker_hostnames" {
  description = "Worker ホスト名リスト"
  type        = list(string)
}

variable "kube_vip" {
  description = "kube-vip 仮想 IP"
  type        = string
}

variable "pod_network_cidr" {
  description = "Pod ネットワーク CIDR"
  type        = string
}

variable "ssh_private_key_path" {
  description = "SSH 秘密鍵パス"
  type        = string
  default     = "~/.ssh/id_rsa"
}
