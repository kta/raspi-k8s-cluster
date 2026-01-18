#!/bin/bash
set -e

# 引数受け取り
VIP=$1
INTERFACE=$2
PRIORITY=$3
STATE=$4
HAPROXY_PORT=$5
NODE_IPS=$6
K8S_VERSION=$7

echo ">>> Starting Common Setup..."

# --- 0. cgroup memory有効化 (Raspberry Pi必須) ---
# Raspberry Pi OS Bookworm以降は /boot/firmware/cmdline.txt
# 古いバージョンは /boot/cmdline.txt
CMDLINE_FILE=""
if [ -f /boot/firmware/cmdline.txt ]; then
	CMDLINE_FILE="/boot/firmware/cmdline.txt"
elif [ -f /boot/cmdline.txt ]; then
	CMDLINE_FILE="/boot/cmdline.txt"
fi

if [ -n "$CMDLINE_FILE" ]; then
	if ! grep -q "cgroup_memory=1" "$CMDLINE_FILE"; then
		echo ">>> Enabling cgroup memory in $CMDLINE_FILE..."
		# cmdline.txtは1行なので、末尾にパラメータを追加
		sed -i 's/$/ cgroup_enable=memory cgroup_memory=1/' "$CMDLINE_FILE"
		echo ">>> cgroup parameters added. A REBOOT is required!"
		echo ">>> Please reboot all nodes and re-run this playbook."
		exit 100
	else
		echo ">>> cgroup memory already enabled"
	fi
fi

# --- 1. OS設定 ---
# swapを完全に無効化（zramも含む）
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Raspberry Pi OSのスワップ管理システムを無効化
echo ">>> Disabling Raspberry Pi swap management..."
# rpi-swapの設定ファイル自体を無効化（Raspberry Pi OS最新版）
if [ -f /etc/rpi/swap.conf ]; then
	mv /etc/rpi/swap.conf /etc/rpi/swap.conf.disabled 2>/dev/null || true
fi
# 念のため、設定ディレクトリ全体も無効化
if [ -d /etc/rpi ]; then
	# rpi ディレクトリ内の他のファイルも確認
	if [ -d /etc/rpi/swap.conf.d ] && [ -n "$(ls -A /etc/rpi/swap.conf.d 2>/dev/null)" ]; then
		mv /etc/rpi/swap.conf.d /etc/rpi/swap.conf.d.disabled 2>/dev/null || true
	fi
fi

# zram-generatorの設定を無効化（古いバージョン用）
echo ">>> Disabling zram-generator configuration..."
if [ -f /usr/lib/systemd/zram-generator.conf ]; then
	mv /usr/lib/systemd/zram-generator.conf /usr/lib/systemd/zram-generator.conf.disabled 2>/dev/null || true
fi
if [ -f /etc/systemd/zram-generator.conf ]; then
	mv /etc/systemd/zram-generator.conf /etc/systemd/zram-generator.conf.disabled 2>/dev/null || true
fi
# zram-generator.conf.d ディレクトリも無効化
if [ -d /usr/lib/systemd/zram-generator.conf.d ]; then
	mv /usr/lib/systemd/zram-generator.conf.d /usr/lib/systemd/zram-generator.conf.d.disabled 2>/dev/null || true
fi
if [ -d /etc/systemd/zram-generator.conf.d ]; then
	mv /etc/systemd/zram-generator.conf.d /etc/systemd/zram-generator.conf.d.disabled 2>/dev/null || true
fi

# zramデバイスがまだ存在する場合は停止して削除
if [ -e /dev/zram0 ]; then
	echo ">>> Stopping and removing zram0 device..."
	# スワップを停止
	swapoff /dev/zram0 2>/dev/null || true
	# systemdのzramサービスを停止してマスク（完全無効化）
	systemctl stop dev-zram0.swap 2>/dev/null || true
	systemctl mask dev-zram0.swap 2>/dev/null || true
	systemctl stop 'systemd-zram-setup@zram0.service' 2>/dev/null || true
	systemctl mask 'systemd-zram-setup@zram0.service' 2>/dev/null || true
	# zramデバイスをリセット
	echo 1 >/sys/block/zram0/reset 2>/dev/null || true
	# zramモジュールをアンロード
	rmmod zram 2>/dev/null || true
fi

# systemd-generatorの出力ファイルを削除（再起動時に再生成されないようにする）
echo ">>> Removing systemd-generator output files..."
rm -f /run/systemd/generator/dev-zram0.swap 2>/dev/null || true
rm -f /run/systemd/generator/systemd-zram-setup@zram0.service 2>/dev/null || true
rm -rf /run/systemd/generator/systemd-zram-setup@zram0.service.d 2>/dev/null || true

# systemd-generatorを再実行してzram設定を削除
systemctl daemon-reload

# 古いzramサービスも無効化（古いOS用）
systemctl disable --now zramswap.service 2>/dev/null || true
systemctl disable --now zram-config.service 2>/dev/null || true
systemctl mask zramswap.service 2>/dev/null || true
systemctl mask zram-config.service 2>/dev/null || true

# 確認: スワップが完全に無効化されているか
if [ "$IS_CI" != "true" ] && grep -q -E '(swap|zram)' /proc/swaps 2>/dev/null; then
	echo "❌ ERROR: Swap is still active after disabling!"
	cat /proc/swaps
	echo ">>> This system requires a reboot to fully disable swap."
	echo ">>> Exiting with code 100 to trigger reboot..."
	exit 100
elif [ "$IS_CI" = "true" ] && grep -q -E '(swap|zram)' /proc/swaps 2>/dev/null; then
	echo "⚠️  CI Environment detected. Ignoring active swap in /proc/swaps (Host swap)."
fi
echo "✅ Swap disabled successfully"

cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.ipv4.ip_nonlocal_bind           = 1
EOF
sysctl --system

# --- 2. パッケージインストール ---
# Debian Trixie対応: 依存関係の競合を避けるため update を念入りに
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release keepalived haproxy containerd conntrack ethtool

# --- 3. Containerd設定 ---
mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
systemctl restart containerd

# --- 4. K8sツールインストール ---
# kubeadm コマンドが存在しない場合はインストール（gpgファイルだけでは不十分）
if ! command -v kubeadm &>/dev/null; then
	echo ">>> Installing Kubernetes tools (kubeadm, kubelet, kubectl)..."

	# GPGキーが壊れている可能性があるので一度削除
	rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg
	rm -f /etc/apt/sources.list.d/kubernetes.list

	mkdir -p /etc/apt/keyrings
	curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
	echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
	apt-get update
	apt-get install -y kubelet kubeadm kubectl
	apt-mark hold kubelet kubeadm kubectl

	# インストール確認
	if ! command -v kubeadm &>/dev/null; then
		echo "❌ Failed to install kubeadm!"
		exit 1
	fi
	echo "✅ Kubernetes tools installed successfully"
else
	echo ">>> Kubernetes tools already installed: $(kubeadm version -o short 2>/dev/null || echo 'unknown')"
fi

# --- 4.5. CNI plugin path fix ---
# Flannelは /opt/cni/bin/ にプラグインをインストールするが、
# kubeletが /usr/lib/cni を見ることがあるため、シンボリックリンクを作成
mkdir -p /usr/lib/cni
ln -sf /opt/cni/bin/* /usr/lib/cni/ 2>/dev/null || true

# --- 4.6. kubelet node-ip設定 ---
# 指定されたインターフェースからIPアドレスを取得してkubeletに設定
NODE_IP=$(ip -4 addr show "${INTERFACE}" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
if [ -n "${NODE_IP}" ]; then
	echo ">>> Configuring kubelet with node-ip: ${NODE_IP}"
	mkdir -p /etc/default
	echo "KUBELET_EXTRA_ARGS=--node-ip=${NODE_IP}" >/etc/default/kubelet
	# kubeletがすでに起動している場合は再起動
	systemctl daemon-reload
	if systemctl is-active --quiet kubelet; then
		systemctl restart kubelet
	fi
else
	echo "⚠️  Warning: Could not determine IP for interface ${INTERFACE}"
fi

# --- 5. Keepalived設定 ---
mkdir -p /etc/keepalived
mkdir -p /etc/default

# ビルド設定ファイルが削除されている場合、手動で作成
if [ ! -f /etc/keepalived/keepalived.config-opts ]; then
	cat <<'EOFBUILD' >/etc/keepalived/keepalived.config-opts
--build=aarch64-linux-gnu --prefix=/usr --includedir=/usr/include --mandir=/usr/share/man --infodir=/usr/share/info --sysconfdir=/etc --localstatedir=/var --disable-option-checking --disable-silent-rules --libdir=/usr/lib/aarch64-linux-gnu --runstatedir=/run --disable-maintainer-mode --disable-dependency-tracking --enable-snmp --enable-sha1 --enable-snmp-rfcv2 --enable-snmp-rfcv3 --enable-dbus --enable-json --enable-bfd --enable-regex --enable-log-file --enable-reproducible-build --with-init=systemd build_alias=aarch64-linux-gnu CFLAGS=-g -O2 -Werror=implicit-function-declaration -ffile-prefix-map=/build/reproducible-path/keepalived-2.3.3=. -fstack-protector-strong -fstack-clash-protection -Wformat -Werror=format-security -mbranch-protection=standard LDFLAGS=-Wl,-z,relro CPPFLAGS=-Wdate-time -D_FORTIFY_SOURCE=2
EOFBUILD
fi

cat <<EOF >/etc/default/keepalived
# Options to pass to keepalived

# DAEMON_ARGS are appended to the keepalived command-line
DAEMON_ARGS=""
EOF

cat <<EOF >/etc/keepalived/keepalived.conf
vrrp_instance VI_1 {
    state ${STATE}
    interface ${INTERFACE}
    virtual_router_id 51
    priority ${PRIORITY}
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass k8s_secret
    }
    virtual_ipaddress {
        ${VIP}
    }
}
EOF

# 設定ファイルのチェック
echo ">>> Checking Keepalived config..."
if [ ! -f /etc/keepalived/keepalived.conf ]; then
	echo "❌ Keepalived config not found!"
	exit 1
fi
cat /etc/keepalived/keepalived.conf

# Keepalivedの起動
systemctl stop keepalived || true
systemctl start keepalived
sleep 2
if ! systemctl is-active --quiet keepalived; then
	echo "❌ Keepalived failed to start!"
	systemctl status keepalived --no-pager --lines=50 || true
	journalctl -xeu keepalived.service --no-pager -n 50 || true
	exit 1
fi
echo "✅ Keepalived started successfully"

# --- 6. HAProxy設定 (修正版) ---
# ディレクトリがないとSocketエラーになる場合があるため作成
mkdir -p /run/haproxy
mkdir -p /etc/haproxy

# まずベース設定を書く (mode tcp に統一)
cat <<EOF >/etc/haproxy/haproxy.cfg
global
    log /dev/log    local0
    log /dev/log    local1 notice
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000

frontend k8s-api
    bind *:${HAPROXY_PORT}
    mode tcp
    option tcplog
    default_backend k8s-api-backend

backend k8s-api-backend
    mode tcp
    option tcp-check
    balance roundrobin
EOF

# サーバーリストをループで追記する (ここが修正ポイント！)
i=1
for ip in $(echo "$NODE_IPS" | tr "," " "); do
	echo "    server k8s-${i} ${ip}:6443 check fall 3 rise 2" >>/etc/haproxy/haproxy.cfg
	i=$((i + 1))
done

# 設定ファイルの構文チェック
echo ">>> Checking HAProxy config..."
if ! haproxy -c -f /etc/haproxy/haproxy.cfg; then
	echo "❌ HAProxy config is invalid!"
	cat /etc/haproxy/haproxy.cfg
	exit 1
fi

systemctl restart haproxy

echo ">>> Common Setup Complete."
