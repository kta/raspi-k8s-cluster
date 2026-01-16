#!/bin/bash
set -e

JOIN_CMD="$1"

echo ">>> Starting Secondary Master Init..."

# 1. すでに参加済みかチェック
if [ -f /etc/kubernetes/kubelet.conf ]; then
    echo "Already joined to cluster."
else
    echo "Joining cluster..."
    NODE_IP=$(ip -4 addr show eth1 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
    eval "$JOIN_CMD --apiserver-advertise-address=${NODE_IP}"
fi

# 2. Flannelプラグインのインストール待機
echo "Waiting for Flannel to install CNI plugins..."
MAX_WAIT=180
ELAPSED=0
while [ ! -f /opt/cni/bin/flannel ] && [ $ELAPSED -lt $MAX_WAIT ]; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo "  ... waiting ($ELAPSED/${MAX_WAIT}s)"
done

if [ ! -f /opt/cni/bin/flannel ]; then
    echo "ERROR: Flannel plugin not installed after ${MAX_WAIT}s"
    exit 1
fi

# 3. CNIシンボリックリンク作成
echo "Creating CNI plugin symlinks..."
mkdir -p /usr/lib/cni
ln -sf /opt/cni/bin/* /usr/lib/cni/
echo "CNI plugin symlinks created."

# 4. kubelet再起動
echo "Restarting kubelet..."
systemctl restart kubelet

echo ">>> Secondary Master Init Complete!"
