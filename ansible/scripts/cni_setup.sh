#!/bin/bash
set -e

# KUBECONFIG設定
export KUBECONFIG=/etc/kubernetes/admin.conf

echo ">>> Setting up CNI on Primary Master..."

# 1. Flannel DaemonSet が作成されるまで待機 (kube-flannelネームスペース)
echo "Waiting for Flannel DaemonSet..."
MAX_WAIT=150
ELAPSED=0
while ! kubectl get daemonset -n kube-flannel kube-flannel-ds >/dev/null 2>&1 && [ $ELAPSED -lt $MAX_WAIT ]; do
	sleep 5
	ELAPSED=$((ELAPSED + 5))
	echo "  ... waiting ($ELAPSED/${MAX_WAIT}s)"
done

if ! kubectl get daemonset -n kube-flannel kube-flannel-ds >/dev/null 2>&1; then
	echo "ERROR: Flannel DaemonSet not found after ${MAX_WAIT}s"
	echo "Checking Flannel resources in kube-flannel namespace:"
	kubectl get all -n kube-flannel || echo "No Flannel resources found"
	echo "Checking Flannel resources in kube-system namespace:"
	kubectl get all -n kube-system | grep -i flannel || echo "No Flannel resources in kube-system"
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

# 3. CNIシンボリックリンク作成（Flannelバイナリを含む）
echo "Creating CNI plugin symlinks..."
mkdir -p /usr/lib/cni
# 既存のシンボリックリンクを削除してから再作成
rm -f /usr/lib/cni/*
ln -sf /opt/cni/bin/* /usr/lib/cni/
echo "CNI plugin symlinks created."
# Check for expected CNI plugins using glob patterns
if compgen -G "/usr/lib/cni/flannel" >/dev/null &&
	compgen -G "/usr/lib/cni/bridge" >/dev/null &&
	compgen -G "/usr/lib/cni/host-local" >/dev/null; then
	echo "All expected CNI plugins found."
else
	echo "Warning: Some expected CNI plugins not found"
	ls -la /usr/lib/cni/
fi

# 4. kubelet再起動
echo "Restarting kubelet..."
systemctl restart kubelet

echo ">>> CNI Setup Complete!"
