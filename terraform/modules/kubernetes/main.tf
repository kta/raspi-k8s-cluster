locals {
  first_control_plane_ip = var.control_plane_ips[0]
}

variable "kube_vip_manifest" {
  description = "kube-vip マニフェスト（main.tf から注入）"
  type        = string
}

# 最初の Control Plane 初期化
resource "null_resource" "k8s_init_first_control_plane" {
  connection {
    type        = "ssh"
    user        = "debian"
    host        = local.first_control_plane_ip
    private_key = file(pathexpand(var.ssh_private_key_path))
    timeout     = "5m"
  }

  # kube-vip マニフェスト配置
  provisioner "file" {
    content     = var.kube_vip_manifest
    destination = "/tmp/kube-vip.yaml"
  }

  # kubeadm init 実行
  provisioner "remote-exec" {
    inline = [
      "set -e",
      "echo 'Starting Kubernetes initialization...'",
      "sudo mkdir -p /etc/kubernetes/manifests",
      "sudo cp /tmp/kube-vip.yaml /etc/kubernetes/manifests/kube-vip.yaml",
      "sudo kubeadm init --control-plane-endpoint=${var.kube_vip}:6443 --upload-certs --pod-network-cidr=${var.pod_network_cidr}",
      "mkdir -p $HOME/.kube",
      "sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config",
      "sudo chown $(id -u):$(id -g) $HOME/.kube/config",
      "echo 'Kubernetes initialization completed!'",
    ]
  }
}

# kubeconfig 取得
resource "null_resource" "k8s_get_kubeconfig" {
  depends_on = [null_resource.k8s_init_first_control_plane]

  provisioner "local-exec" {
    command = <<-EOT
      ssh -i ${pathexpand(var.ssh_private_key_path)} \
          -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          debian@${local.first_control_plane_ip} \
          'cat $HOME/.kube/config' > ${path.module}/kubeconfig.yaml
      
      # VIP アドレスに書き換え
      sed -i.bak 's|server: https://.*:6443|server: https://${var.kube_vip}:6443|' ${path.module}/kubeconfig.yaml
      rm -f ${path.module}/kubeconfig.yaml.bak
    EOT
  }
}

# Join コマンド生成
resource "null_resource" "k8s_generate_join_command" {
  depends_on = [null_resource.k8s_get_kubeconfig]

  provisioner "local-exec" {
    command = <<-EOT
      ssh -i ${pathexpand(var.ssh_private_key_path)} \
          -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          debian@${local.first_control_plane_ip} \
          'sudo kubeadm token create --print-join-command' > ${path.module}/join-worker.sh

      ssh -i ${pathexpand(var.ssh_private_key_path)} \
          -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          debian@${local.first_control_plane_ip} \
          'echo "$(sudo kubeadm token create --print-join-command) --control-plane --certificate-key $(sudo kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1)"' > ${path.module}/join-control-plane.sh
    EOT
  }
}

# 残りの Control Plane を Join
resource "null_resource" "k8s_join_control_planes" {
  count      = length(var.control_plane_ips) - 1
  depends_on = [null_resource.k8s_generate_join_command]

  connection {
    type        = "ssh"
    user        = "debian"
    host        = var.control_plane_ips[count.index + 1]
    private_key = file(pathexpand(var.ssh_private_key_path))
    timeout     = "5m"
  }

  provisioner "file" {
    source      = "${path.module}/join-control-plane.sh"
    destination = "/tmp/join-control-plane.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "echo 'Joining control plane ${var.control_plane_hostnames[count.index + 1]}...'",
      "chmod +x /tmp/join-control-plane.sh",
      "sudo /bin/bash /tmp/join-control-plane.sh",
      "mkdir -p $HOME/.kube",
      "sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config",
      "sudo chown $(id -u):$(id -g) $HOME/.kube/config",
      "echo 'Control plane joined successfully!'",
    ]
  }
}

# Worker ノードを Join
resource "null_resource" "k8s_join_workers" {
  count      = length(var.worker_ips)
  depends_on = [null_resource.k8s_join_control_planes]

  connection {
    type        = "ssh"
    user        = "debian"
    host        = var.worker_ips[count.index]
    private_key = file(pathexpand(var.ssh_private_key_path))
    timeout     = "5m"
  }

  provisioner "file" {
    source      = "${path.module}/join-worker.sh"
    destination = "/tmp/join-worker.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "echo 'Joining worker ${var.worker_hostnames[count.index]}...'",
      "chmod +x /tmp/join-worker.sh",
      "sudo /bin/bash /tmp/join-worker.sh",
      "echo 'Worker joined successfully!'",
    ]
  }
}

# kubeconfig を読み込み可能にするためのダミーリソース
resource "null_resource" "k8s_cluster_ready" {
  depends_on = [null_resource.k8s_join_workers]

  provisioner "local-exec" {
    command = "echo 'Kubernetes cluster is ready!'"
  }
}
