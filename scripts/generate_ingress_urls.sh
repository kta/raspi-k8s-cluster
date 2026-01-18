#!/bin/bash
# nip.io を使ったIngress URLを生成するスクリプト
#
# 使い方:
#   ./generate_ingress_urls.sh [environment]
#
# 例:
#   ./generate_ingress_urls.sh production
#   ./generate_ingress_urls.sh vagrant

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

# IP を nip.io 形式に変換（ドット→ハイフン）
IP_NIP=$(echo "$INGRESS_IP" | tr '.' '-')

# sslip.io 形式（ドットをそのまま使用）
IP_SSLIP="$INGRESS_IP"

echo "=========================================="
echo "📋 環境: $ENVIRONMENT"
echo "📍 Ingress IP: $INGRESS_IP"
echo ""
echo "✨ nip.io を使った URL:"
echo "  🔹 ArgoCD:   http://argocd-$IP_NIP.nip.io"
echo "  🔹 Atlantis: http://atlantis-$IP_NIP.nip.io"
echo "  🔹 Traefik:  http://traefik-$IP_NIP.nip.io"
echo ""
echo "✨ sslip.io を使った URL:"
echo "  🔹 ArgoCD:   http://argocd.$IP_SSLIP.sslip.io"
echo "  🔹 Atlantis: http://atlantis.$IP_SSLIP.sslip.io"
echo "  �� Traefik:  http://traefik.$IP_SSLIP.sslip.io"
echo ""
echo "📝 Ingress マニフェストの例:"
echo "----------------------------------------"
cat <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-ingress
  namespace: argocd
spec:
  rules:
  - host: argocd-$IP_NIP.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 443
EOF
echo "----------------------------------------"
echo ""
echo "💡 ヒント:"
echo "  - nip.io: ハイフン区切りのIP"
echo "  - sslip.io: ドット区切りのIP"
echo "  - どちらも /etc/hosts 編集不要"
echo "  - インターネット接続が必要"
echo "=========================================="
