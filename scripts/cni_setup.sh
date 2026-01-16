#!/bin/bash
set -e

echo ">>> Setting up CNI on Primary Master..."

# 1. Flannel DaemonSet が作成されるまで待機
echo "Waiting for Flannel DaemonSet..."
MAX_WAIT=150
ELAPSED=0
while ! kubectl get daemonset -n kube-system kube-flannel-ds >/dev/null 2>&1 && [ $ELAPSED -lt $MAX_WAIT ]; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo "  ... waiting ($ELAPSED/${MAX_WAIT}s)"
done

if ! kubectl get daemonset -n kube-system kube-flannel-ds >/dev/null 2>&1; then
    echo "ERROR: Flannel DaemonSet not found after ${MAX_WAIT}s"
    exit 1
fi

# 2. Flannelプラグインのインストール待機
echo "Waiting for Flannel to install CNI plugins on this node..."
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

echo ">>> CNI Setup Complete!"
