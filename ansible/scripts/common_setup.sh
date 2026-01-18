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

# --- 1. OS設定 ---
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

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
if [ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]; then
	mkdir -p /etc/apt/keyrings
	curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
	echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
	apt-get update
	apt-get install -y kubelet kubeadm kubectl
	apt-mark hold kubelet kubeadm kubectl
fi

# --- 4.5. CNI plugin path fix ---
# Flannelは /opt/cni/bin/ にプラグインをインストールするが、
# kubeletが /usr/lib/cni を見ることがあるため、シンボリックリンクを作成
mkdir -p /usr/lib/cni
ln -sf /opt/cni/bin/* /usr/lib/cni/ 2>/dev/null || true

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
