#!/bin/bash
# Kubernetes サービスに自動的にポートフォワードするスクリプト
#
# 使い方:
#   ./port_forward_services.sh [service_name]
#
# 例:
#   ./port_forward_services.sh argocd
#   ./port_forward_services.sh atlantis
#   ./port_forward_services.sh traefik
#   ./port_forward_services.sh all

set -euo pipefail

SERVICE="${1:-all}"

# カラーコード
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ポートフォワード関数
forward_argocd() {
	echo -e "${CYAN}🚀 ArgoCD にポートフォワード中...${NC}"
	echo -e "${GREEN}✓${NC} http://localhost:8080 でアクセス可能"
	echo -e "${YELLOW}初期パスワード取得:${NC}"
	echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
	echo ""
	kubectl port-forward -n argocd svc/argocd-server 8080:443
}

forward_atlantis() {
	echo -e "${CYAN}🚀 Atlantis にポートフォワード中...${NC}"
	echo -e "${GREEN}✓${NC} http://localhost:4141 でアクセス可能"
	echo ""
	kubectl port-forward -n atlantis svc/atlantis 4141:80
}

forward_traefik() {
	echo -e "${CYAN}🚀 Traefik Dashboard にポートフォワード中...${NC}"
	echo -e "${GREEN}✓${NC} http://localhost:9000 でアクセス可能"
	echo ""
	kubectl port-forward -n traefik svc/traefik 9000:9000
}

forward_all() {
	echo -e "${CYAN}🚀 全サービスにポートフォワード中...${NC}"
	echo ""
	echo "以下のポートでアクセス可能になります:"
	echo -e "  ${GREEN}ArgoCD:${NC}    http://localhost:8080"
	echo -e "  ${GREEN}Atlantis:${NC}  http://localhost:4141"
	echo -e "  ${GREEN}Traefik:${NC}   http://localhost:9000"
	echo ""
	echo -e "${YELLOW}注意: Ctrl+C で停止します${NC}"
	echo ""

	# バックグラウンドでポートフォワードを起動
	kubectl port-forward -n argocd svc/argocd-server 8080:443 &
	PID_ARGOCD=$!

	kubectl port-forward -n atlantis svc/atlantis 4141:80 &
	PID_ATLANTIS=$!

	kubectl port-forward -n traefik svc/traefik 9000:9000 &
	PID_TRAEFIK=$!

	# クリーンアップハンドラー
	cleanup() {
		echo ""
		echo -e "${YELLOW}ポートフォワードを停止中...${NC}"
		kill $PID_ARGOCD $PID_ATLANTIS $PID_TRAEFIK 2>/dev/null || true
		echo -e "${GREEN}✓ 停止しました${NC}"
		exit 0
	}

	trap cleanup INT TERM

	# フォアグラウンドで待機
	wait
}

# メイン処理
case "$SERVICE" in
argocd)
	forward_argocd
	;;
atlantis)
	forward_atlantis
	;;
traefik)
	forward_traefik
	;;
all)
	forward_all
	;;
*)
	echo "使い方: $0 {argocd|atlantis|traefik|all}"
	exit 1
	;;
esac
