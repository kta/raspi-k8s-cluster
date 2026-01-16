# Cloud-Init 設定ファイル（local ストレージに保存 - snippets は Ceph 非対応）
resource "proxmox_virtual_environment_file" "cloud_init" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.node_name

  source_raw {
    data      = var.cloud_init_user_data
    file_name = "${var.vm_name}-cloud-init.yaml"
  }
}

# VM 作成（Cloud Image から直接起動）
resource "proxmox_virtual_environment_vm" "vm" {
  name        = var.vm_name
  node_name   = var.node_name
  vm_id       = var.vm_id
  description = "Managed by Terraform - Kubernetes Cluster Node"

  # ARM64 用設定
  machine = "virt"
  bios    = "ovmf"

  cpu {
    cores = var.cpu_cores
    type  = "host"
  }

  memory {
    dedicated = var.memory_mb
  }

  # EFI ディスク（ARM64 必須）
  efi_disk {
    datastore_id = var.storage_pool
    type         = "4m"
  }

  # OS ディスク（Cloud Image から作成）
  disk {
    datastore_id = var.storage_pool
    file_id      = var.cloud_image_file_id
    interface    = "scsi0"
    size         = var.disk_size_gb
    file_format  = "raw"
    iothread     = true
    discard      = "on"
  }

  # SCSI コントローラー
  scsi_hardware = "virtio-scsi-single"

  # ネットワーク
  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  # Cloud-Init 設定
  initialization {
    datastore_id = var.storage_pool

    ip_config {
      ipv4 {
        address = "${var.ip_address}/${var.subnet}"
        gateway = var.gateway
      }
    }

    dns {
      servers = [var.dns]
    }

    user_data_file_id = proxmox_virtual_environment_file.cloud_init.id
  }

  # シリアルコンソール（デバッグ用）
  serial_device {}

  # VGA（ARM64 では serial のみ使用）
  vga {
    type = "serial0"
  }

  # Agent
  agent {
    enabled = true
  }

  # 起動時に開始
  started    = true
  on_boot    = true
  boot_order = ["scsi0"]

  lifecycle {
    ignore_changes = [
      network_device,
    ]
  }
}
