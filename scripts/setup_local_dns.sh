#!/bin/bash
# dnsmasq を使ってローカルDNSを自動設定するスクリプト
#
# 使い方:
#   ./setup_local_dns.sh [environment]
#
# 例:
#   ./setup_local_dns.sh production
#   ./setup_local_dns.sh vagrant

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENVIRONMENT="${1:-production}"

if [[ "$ENVIRONMENT" != "production" && "$ENVIRONMENT" != "vagrant" ]]; then
	echo "❌ エラー: environment は production または vagrant である必要があります"
	exit 1
fi

# インベントリファイルを決定
if [[ "$ENVIRONMENT" == "production" ]]; then
	INVENTORY_FILE="$PROJECT_ROOT/ansible/inventory/inventory.ini"
else
	INVENTORY_FILE="$PROJECT_ROOT/ansible/inventory/inventory_vagrant.ini"
fi

if [[ ! -f "$INVENTORY_FILE" ]]; then
	echo "❌ エラー: インベントリファイルが見つかりません: $INVENTORY_FILE"
	exit 1
fi

# ingress_ip を抽出
INGRESS_IP=$(grep "^ingress_ip=" "$INVENTORY_FILE" | head -1 | cut -d'=' -f2 | tr -d ' ')

if [[ -z "$INGRESS_IP" ]]; then
	echo "❌ エラー: ingress_ip がインベントリファイルに見つかりません"
	exit 1
fi

echo "📋 環境: $ENVIRONMENT"
echo "📍 Ingress IP: $INGRESS_IP"
echo ""

# OSを検出
OS="$(uname -s)"

case "$OS" in
Darwin)
	echo "🍎 macOS を検出しました"

	# dnsmasq がインストールされているか確認
	if ! command -v dnsmasq &>/dev/null; then
		echo "❌ dnsmasq がインストールされていません"
		echo ""
		echo "インストール方法:"
		echo "  brew install dnsmasq"
		exit 1
	fi

	# dnsmasq 設定ディレクトリ
	DNSMASQ_DIR="/opt/homebrew/etc/dnsmasq.d"
	if [[ ! -d "$DNSMASQ_DIR" ]]; then
		DNSMASQ_DIR="/usr/local/etc/dnsmasq.d"
	fi

	mkdir -p "$DNSMASQ_DIR" 2>/dev/null || true

	# 設定ファイルを作成
	CONFIG_FILE="$DNSMASQ_DIR/raspi-k8s.conf"

	echo "📝 dnsmasq 設定ファイルを作成中: $CONFIG_FILE"
	sudo tee "$CONFIG_FILE" >/dev/null <<EOF
# Raspberry Pi Kubernetes クラスタ用 DNS 設定
# 環境: $ENVIRONMENT
# 生成日時: $(date '+%Y-%m-%d %H:%M:%S')

# .local ドメインを解決
address=/argocd.local/$INGRESS_IP
address=/atlantis.local/$INGRESS_IP
address=/traefik.local/$INGRESS_IP
EOF

	echo "✅ 設定ファイルを作成しました"
	echo ""

	# dnsmasq を再起動
	echo "🔄 dnsmasq を再起動中..."
	sudo brew services restart dnsmasq || sudo brew services start dnsmasq

	echo "✅ dnsmasq を再起動しました"
	echo ""

	# macOS の DNS resolver 設定
	RESOLVER_DIR="/etc/resolver"
	sudo mkdir -p "$RESOLVER_DIR"

	echo "📝 macOS resolver 設定を作成中..."
	sudo tee "$RESOLVER_DIR/local" >/dev/null <<EOF
nameserver 127.0.0.1
EOF

	echo "✅ macOS resolver 設定を作成しました"
	echo ""

	# DNS キャッシュをクリア
	echo "�� DNS キャッシュをクリア中..."
	sudo dscacheutil -flushcache
	sudo killall -HUP mDNSResponder

	echo "✅ DNS キャッシュをクリアしました"
	;;

Linux)
	echo "🐧 Linux を検出しました"

	# dnsmasq がインストールされているか確認
	if ! command -v dnsmasq &>/dev/null; then
		echo "❌ dnsmasq がインストールされていません"
		echo ""
		echo "インストール方法:"
		echo "  sudo apt-get install dnsmasq     # Debian/Ubuntu"
		echo "  sudo yum install dnsmasq         # CentOS/RHEL"
		exit 1
	fi

	# 設定ファイルを作成
	CONFIG_FILE="/etc/dnsmasq.d/raspi-k8s.conf"

	echo "📝 dnsmasq 設定ファイルを作成中: $CONFIG_FILE"
	sudo tee "$CONFIG_FILE" >/dev/null <<EOF
# Raspberry Pi Kubernetes クラスタ用 DNS 設定
# 環境: $ENVIRONMENT
# 生成日時: $(date '+%Y-%m-%d %H:%M:%S')

# .local ドメインを解決
address=/argocd.local/$INGRESS_IP
address=/atlantis.local/$INGRESS_IP
address=/traefik.local/$INGRESS_IP
EOF

	echo "✅ 設定ファイルを作成しました"
	echo ""

	# dnsmasq を再起動
	echo "🔄 dnsmasq を再起動中..."
	sudo systemctl restart dnsmasq

	echo "✅ dnsmasq を再起動しました"
	;;

*)
	echo "❌ サポートされていないOS: $OS"
	exit 1
	;;
esac

echo ""
echo "=========================================="
echo "✅ ローカルDNS設定が完了しました！"
echo ""
echo "以下のURLでアクセス可能になりました:"
echo "  🔹 http://argocd.local"
echo "  🔹 http://atlantis.local"
echo "  🔹 http://traefik.local"
echo ""
echo "確認方法:"
echo "  nslookup argocd.local"
echo "  ping -c 1 argocd.local"
echo ""
echo "削除方法:"
if [[ "$OS" == "Darwin" ]]; then
	echo "  sudo rm $CONFIG_FILE"
	echo "  sudo rm /etc/resolver/local"
	echo "  sudo brew services restart dnsmasq"
else
	echo "  sudo rm $CONFIG_FILE"
	echo "  sudo systemctl restart dnsmasq"
fi
echo "=========================================="
