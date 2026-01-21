#!/bin/bash
set -e

JOIN_CMD="$1"
VIP="$2"
INTERFACE="$3"

# Error handler - create marker file with error status
error_handler() {
	echo "ERROR: Script failed at line $1" | tee /tmp/secondary_init.done
	exit 1
}
trap 'error_handler ${LINENO}' ERR

echo ">>> Starting Secondary Master Init..."
echo ">>> VIP: ${VIP}"
echo ">>> INTERFACE: ${INTERFACE}"

# クリーンアップ関数
cleanup_failed_join() {
	echo "Cleaning up failed join attempt..."

	# 1. kubeletを停止
	systemctl stop kubelet 2>/dev/null || true
	sleep 2

	# 2. 全てのコンテナを強制停止
	crictl stopp "$(crictl pods -q)" 2>/dev/null || true
	sleep 2
	crictl rmp "$(crictl pods -q)" 2>/dev/null || true

	# 3. etcd Podを確実に削除
	rm -f /etc/kubernetes/manifests/etcd.yaml 2>/dev/null || true
	sleep 5 # etcdが完全に停止するまで待機

	# 4. その他のmanifestを削除
	rm -f /etc/kubernetes/manifests/kube-*.yaml 2>/dev/null || true

	# 5. kubeconfig削除
	rm -f /etc/kubernetes/kubelet.conf 2>/dev/null || true
	rm -f /etc/kubernetes/bootstrap-kubelet.conf 2>/dev/null || true
	rm -f /etc/kubernetes/admin.conf 2>/dev/null || true
	rm -f /etc/kubernetes/controller-manager.conf 2>/dev/null || true
	rm -f /etc/kubernetes/scheduler.conf 2>/dev/null || true

	# 6. PKI証明書を削除（再生成させる）
	rm -rf /etc/kubernetes/pki 2>/dev/null || true

	# 7. etcdデータの完全クリーンアップ
	rm -rf /var/lib/etcd 2>/dev/null || true

	# 8. kubeletデータのクリーンアップ
	rm -rf /var/lib/kubelet/* 2>/dev/null || true

	echo "Cleanup complete"
}

# 1. すでに参加済みかチェック
if [ -f /etc/kubernetes/kubelet.conf ] && systemctl is-active --quiet kubelet; then
	echo "Already joined to cluster and kubelet is running."
else
	echo "Joining cluster..."
	# 指定されたインターフェースからIPアドレスを取得
	if [ -n "$INTERFACE" ]; then
		NODE_IP=$(ip -4 addr show "$INTERFACE" | grep -oP 'inet \K[\d.]+' | grep -v "^${VIP}$" | head -n 1)
	fi
	if [ -z "$NODE_IP" ]; then
		# フォールバック: VIPへのルートのソースIPを使用
		NODE_IP=$(ip route get "${VIP}" | grep -oP 'src \K[\d.]+' | head -n 1)
		if [ "$NODE_IP" = "$VIP" ]; then
			NODE_IP=$(ip route get 8.8.8.8 | grep -oP 'src \K[\d.]+' | head -n 1)
		fi
	fi
	echo ">>> Using NODE_IP: ${NODE_IP}"

	# リトライロジック: etcd同期の問題に対応
	MAX_RETRIES=3
	RETRY_DELAY=30
	for i in $(seq 1 $MAX_RETRIES); do
		echo "Join attempt $i of $MAX_RETRIES..."
		if eval "$JOIN_CMD --apiserver-advertise-address=${NODE_IP}"; then
			echo "Successfully joined the cluster"

			echo "Patching Controller Manager and Scheduler to listen on 0.0.0.0 for metrics scraping..."
			sed -i 's/--bind-address=127.0.0.1/--bind-address=0.0.0.0/' /etc/kubernetes/manifests/kube-controller-manager.yaml
			sed -i 's/--bind-address=127.0.0.1/--bind-address=0.0.0.0/' /etc/kubernetes/manifests/kube-scheduler.yaml
			break
		else
			if [ "$i" -lt $MAX_RETRIES ]; then
				echo "Join failed, cleaning up before retry..."
				cleanup_failed_join
				echo "Waiting ${RETRY_DELAY}s before retry..."
				sleep $RETRY_DELAY
			else
				echo "ERROR: Failed to join cluster after $MAX_RETRIES attempts"
				echo "This may be caused by etcd cluster instability."
				echo "Please try running 'make ansible-reset' and then 'make ansible-setup-vagrant' again."
				exit 1
			fi
		fi
	done
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

# 5. コントロールプレーンノードでもPodをスケジュール可能にする（taint解除）
echo "Removing control-plane taint to allow pod scheduling..."
kubectl --kubeconfig=/etc/kubernetes/admin.conf taint nodes "$(hostname)" node-role.kubernetes.io/control-plane- || true

echo ">>> Secondary Master Init Complete!"

# Create completion marker file
echo "SUCCESS" > /tmp/secondary_init.done
