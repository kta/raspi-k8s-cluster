#!/bin/bash
set -e

VIP=$1
HAPROXY_PORT=$2
TOKEN_FILE="/tmp/k8s_join_command.sh"

echo ">>> Starting Primary Init..."

# 1. クラスター未作成なら init 実行
if [ ! -f /etc/kubernetes/admin.conf ]; then
    echo "Initializing Cluster..."
    # 各ノードのIPアドレスを取得
    NODE_IP=$(ip -4 addr show eth1 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
    kubeadm init --control-plane-endpoint "${VIP}:${HAPROXY_PORT}" \
      --upload-certs \
      --pod-network-cidr=10.244.0.0/16 \
      --apiserver-advertise-address="${NODE_IP}"
    
    mkdir -p /root/.kube
    cp -f /etc/kubernetes/admin.conf /root/.kube/config
    chown root:root /root/.kube/config
    
    # CNI (Flannel) のインストール
    echo "Installing Flannel CNI..."
    if kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml; then
        echo "Flannel manifest applied successfully."
    else
        echo "ERROR: Failed to apply Flannel manifest"
        exit 1
    fi
    
    # MasterにもPodを置けるようにTaint解除 (3台構成なら必須)
    kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
else
    echo "Cluster already initialized."
fi

# 2. 常に新しいJoinコマンドを生成してファイルに書き出す
#    (既存クラスタへの追加時も、これでトークン切れを防げる)
echo "Generating Join Token..."
CMD=$(kubeadm token create --print-join-command)
KEY=$(kubeadm init phase upload-certs --upload-certs | tail -1)

# ファイルに書き出し
echo "$CMD --control-plane --certificate-key $KEY" > $TOKEN_FILE

chmod 600 $TOKEN_FILE
echo ">>> Token saved to $TOKEN_FILE"