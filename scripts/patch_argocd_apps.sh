#!/bin/bash
# ArgoCD Application マニフェストの environment overlay パスを更新
#
# 使い方:
#   ./patch_argocd_apps.sh [environment]
#
# 例:
#   ./patch_argocd_apps.sh production
#   ./patch_argocd_apps.sh vagrant

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENVIRONMENT="${1:-production}"

if [[ "$ENVIRONMENT" != "production" && "$ENVIRONMENT" != "vagrant" ]]; then
	echo "❌ エラー: environment は production または vagrant である必要があります"
	exit 1
fi

echo "🔄 ArgoCD Application マニフェストを $ENVIRONMENT 環境用に更新中..."

# MetalLB config.yaml を更新
METALLB_CONFIG="$PROJECT_ROOT/k8s/infra/metallb/config.yaml"
if [[ -f "$METALLB_CONFIG" ]]; then
	echo "📝 MetalLB config を更新: $METALLB_CONFIG"
	sed -i.bak "s|path: k8s/infra/metallb/overlays/[a-z]*|path: k8s/infra/metallb/overlays/$ENVIRONMENT|g" "$METALLB_CONFIG"
	rm -f "$METALLB_CONFIG.bak"
fi

echo "✅ 完了！環境: $ENVIRONMENT"
