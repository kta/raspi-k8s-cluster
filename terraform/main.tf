# GitHub SSH 公開鍵取得
data "http" "github_ssh_keys" {
  url = "https://github.com/${var.github_username}.keys"
}

locals {
  ssh_public_key = trimspace(data.http.github_ssh_keys.response_body)
}

# Debian 13 Trixie ARM64 Cloud Image ダウンロード
resource "proxmox_virtual_environment_download_file" "debian_cloud_image" {
  node_name    = var.proxmox_nodes[0]
  content_type = "iso"
  datastore_id = "local"

  url       = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-arm64.qcow2"
  file_name = "debian-13-trixie-arm64.img"
}

# Cloud-Init テンプレート生成
locals {
  cloud_init_template = templatefile("${path.module}/../templates/user-data.yaml.tftpl", {
    hostname                = "placeholder"
    timezone                = var.timezone
    ssh_public_key          = local.ssh_public_key
    k8s_version             = var.kubernetes_version
    control_plane_hostnames = var.control_plane_hostnames
    control_plane_ips       = var.control_plane_ips
    worker_hostnames        = var.worker_hostnames
    worker_ips              = var.worker_ips
  })
}

# Control Plane VM デプロイ
module "control_plane_vms" {
  source = "./modules/vm"
  count  = length(var.control_plane_hostnames)

  vm_id                = 201 + count.index
  vm_name              = var.control_plane_hostnames[count.index]
  node_name            = var.proxmox_nodes[count.index]
  ip_address           = var.control_plane_ips[count.index]
  gateway              = var.network_gateway
  dns                  = var.network_dns
  subnet               = var.network_subnet
  cpu_cores            = var.vm_cpu_cores
  memory_mb            = var.vm_memory_mb
  disk_size_gb         = var.vm_disk_size_gb
  storage_pool         = var.proxmox_storage
  cloud_image_file_id  = proxmox_virtual_environment_download_file.debian_cloud_image.id
  cloud_init_user_data = replace(local.cloud_init_template, "placeholder", var.control_plane_hostnames[count.index])
}

# Worker VM デプロイ
module "worker_vms" {
  source = "./modules/vm"
  count  = length(var.worker_hostnames)

  vm_id                = 211 + count.index
  vm_name              = var.worker_hostnames[count.index]
  node_name            = var.proxmox_nodes[count.index]
  ip_address           = var.worker_ips[count.index]
  gateway              = var.network_gateway
  dns                  = var.network_dns
  subnet               = var.network_subnet
  cpu_cores            = var.vm_cpu_cores
  memory_mb            = var.vm_memory_mb
  disk_size_gb         = var.vm_disk_size_gb
  storage_pool         = var.proxmox_storage
  cloud_image_file_id  = proxmox_virtual_environment_download_file.debian_cloud_image.id
  cloud_init_user_data = replace(local.cloud_init_template, "placeholder", var.worker_hostnames[count.index])
}

# VM 起動待機（Cloud-Init 完了まで）
resource "time_sleep" "wait_for_cloud_init" {
  depends_on = [
    module.control_plane_vms,
    module.worker_vms
  ]

  create_duration = "180s"
}

# Kubernetes ブートストラップ
module "kubernetes" {
  source     = "./modules/kubernetes"
  depends_on = [time_sleep.wait_for_cloud_init]

  control_plane_ips       = var.control_plane_ips
  control_plane_hostnames = var.control_plane_hostnames
  worker_ips              = var.worker_ips
  worker_hostnames        = var.worker_hostnames
  kube_vip                = var.kube_vip
  pod_network_cidr        = var.kubernetes_pod_network_cidr
  ssh_private_key_path    = var.ssh_private_key_path
  kube_vip_manifest = templatefile("${path.module}/../templates/kube-vip-manifest.yaml.tftpl", {
    vip_address       = var.kube_vip
    network_interface = var.network_interface
  })
}

# CNI (Flannel) インストール
resource "helm_release" "flannel" {
  depends_on = [module.kubernetes]

  name             = "flannel"
  repository       = "https://flannel-io.github.io/flannel/"
  chart            = "flannel"
  namespace        = "kube-flannel"
  create_namespace = true

  set {
    name  = "podCidr"
    value = var.kubernetes_pod_network_cidr
  }
}

# ArgoCD インストール
module "argocd" {
  source     = "./modules/argocd"
  depends_on = [helm_release.flannel]
}

