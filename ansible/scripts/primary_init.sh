#!/bin/bash
set -e

VIP=$1
HAPROXY_PORT=$2
INTERFACE=$3
TOKEN_FILE="/tmp/k8s_join_command.sh"

echo ">>> Starting Primary Init..."
echo ">>> Using Interface: ${INTERFACE}"

# 1. クラスター未作成なら init 実行
if [ ! -f /etc/kubernetes/admin.conf ]; then
	echo "Initializing Cluster..."
	# 指定されたインターフェースからIPアドレスを取得
	# VIPがKeepalivedで設定済みの場合、route getはVIP自体を返すため、インターフェースから直接取得する
	if [ -n "$INTERFACE" ]; then
		NODE_IP=$(ip -4 addr show "$INTERFACE" | grep -oP 'inet \K[\d.]+' | grep -v "^${VIP}$" | head -n 1)
	fi
	if [ -z "$NODE_IP" ]; then
		# フォールバック: VIPへのルートのソースIPを使用（VIP以外）
		NODE_IP=$(ip route get "${VIP}" | grep -oP 'src \K[\d.]+' | head -n 1)
		if [ "$NODE_IP" = "$VIP" ]; then
			NODE_IP=$(ip route get 8.8.8.8 | grep -oP 'src \K[\d.]+' | head -n 1)
		fi
	fi
	echo ">>> Using NODE_IP: ${NODE_IP}"
	kubeadm init --control-plane-endpoint "${VIP}:${HAPROXY_PORT}" \
		--upload-certs \
		--pod-network-cidr=10.244.0.0/16 \
		--apiserver-advertise-address="${NODE_IP}"

	echo "Patching Controller Manager and Scheduler to listen on 0.0.0.0 for metrics scraping..."
	sed -i 's/--bind-address=127.0.0.1/--bind-address=0.0.0.0/' /etc/kubernetes/manifests/kube-controller-manager.yaml
	sed -i 's/--bind-address=127.0.0.1/--bind-address=0.0.0.0/' /etc/kubernetes/manifests/kube-scheduler.yaml

	mkdir -p /root/.kube
	cp -f /etc/kubernetes/admin.conf /root/.kube/config
	chown root:root /root/.kube/config

	# CNI (Flannel) のインストール
	echo "Installing Flannel CNI..."
	# ローカルの修正済みマニフェストを使用（--iface を動的に設定）
	# NOTE: k8s/infrastructure/01-system/cni/kube-flannel.yml は ArgoCDで管理するが、
	# 初回クラスタ起動時はまだArgoCDが動いていないため、手動で適用する必要がある。
	# Vagrant環境では /vagrant/k8s/infrastructure/01-system/cni/kube-flannel.yml
	# から読み込む。
	if [ -f /vagrant/k8s/infrastructure/01-system/cni/kube-flannel.yml ]; then
		FLANNEL_MANIFEST="/vagrant/k8s/infrastructure/01-system/cni/kube-flannel.yml"
	elif [ -f /tmp/kube-flannel.yml ]; then
		FLANNEL_MANIFEST="/tmp/kube-flannel.yml"
	else
		FLANNEL_MANIFEST=""
	fi

	if [ -n "$FLANNEL_MANIFEST" ]; then
		echo "Using local Flannel manifest: $FLANNEL_MANIFEST"
		# 一時ファイルにコピーしてパッチを適用（元ファイルは変更しない）
		cp "$FLANNEL_MANIFEST" /tmp/flannel-patched.yml

		# インターフェースが指定されていれば、マニフェストを動的にパッチ
		if [ -n "$INTERFACE" ]; then
			echo "Patching Flannel manifest to use interface: $INTERFACE"
			# 既存の --iface=XXX を置換、または --kube-subnet-mgr の後に追加
			if grep -q "\-\-iface=" /tmp/flannel-patched.yml; then
				# 既存の --iface を置換
				sed -i "s/--iface=.*/--iface=$INTERFACE/" /tmp/flannel-patched.yml
			else
				# --iface が存在しない場合は --kube-subnet-mgr の次の行に追加
				sed -i "/--kube-subnet-mgr/a\        - --iface=$INTERFACE" /tmp/flannel-patched.yml
			fi
		fi

		if kubectl apply -f /tmp/flannel-patched.yml; then
			echo "Flannel manifest applied successfully."
		else
			echo "ERROR: Failed to apply Flannel manifest"
			exit 1
		fi
	else
		echo "Local manifest not found, downloading from upstream..."
		if kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml; then
			echo "Flannel manifest applied successfully."
			echo "WARNING: Upstream manifest does not include --iface. Manual patching may be required."
		else
			echo "ERROR: Failed to apply Flannel manifest"
			exit 1
		fi
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
echo "$CMD --control-plane --certificate-key $KEY" >$TOKEN_FILE

chmod 600 $TOKEN_FILE
echo ">>> Token saved to $TOKEN_FILE"
