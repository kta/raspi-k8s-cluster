#!/usr/bin/env bash
# =============================================================================
# Application Path Update Script
# =============================================================================
# このスクリプトは、ArgoCD Application定義のパスを新しいレイヤー構造に更新します
#
# 使用方法:
#   bash update_application_paths.sh
#
# =============================================================================

set -euo pipefail

# カラー出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGOCD_APPS_DIR="${SCRIPT_DIR}/infrastructure/00-argocd-apps/argocd-apps"

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# =============================================================================
# パス更新関数
# =============================================================================

update_path() {
    local file="$1"
    local old_path="$2"
    local new_path="$3"
    
    # macOS互換のsedを使用
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|${old_path}|${new_path}|g" "$file"
    else
        sed -i "s|${old_path}|${new_path}|g" "$file"
    fi
}

# =============================================================================
# パス更新マッピング
# =============================================================================

log_info "Application定義のパスを更新中..."
echo ""

updated_files=0

# 01-system
log_info "【01-system】パス更新"
find "${ARGOCD_APPS_DIR}" -name "*.yaml" -type f | while read -r file; do
    if grep -q "k8s/infrastructure/cni" "$file"; then
        update_path "$file" "k8s/infrastructure/cni" "k8s/infrastructure/01-system/cni"
        log_success "$(basename "$file"): cni パス更新"
        ((updated_files++)) || true
    fi
done
echo ""

# 02-network
log_info "【02-network】パス更新"
find "${ARGOCD_APPS_DIR}" -name "*.yaml" -type f | while read -r file; do
    if grep -q "k8s/infrastructure/metallb" "$file"; then
        update_path "$file" "k8s/infrastructure/metallb" "k8s/infrastructure/02-network/metallb"
        log_success "$(basename "$file"): metallb パス更新"
    fi
    if grep -q "k8s/infrastructure/traefik" "$file"; then
        update_path "$file" "k8s/infrastructure/traefik" "k8s/infrastructure/02-network/traefik"
        log_success "$(basename "$file"): traefik パス更新"
    fi
    if grep -q "k8s/infrastructure/cert-manager-resources" "$file"; then
        update_path "$file" "k8s/infrastructure/cert-manager-resources" "k8s/infrastructure/02-network/cert-manager-resources"
        log_success "$(basename "$file"): cert-manager-resources パス更新"
    fi
    if grep -q "k8s/infrastructure/cert-manager" "$file" && ! grep -q "cert-manager-resources" "$file"; then
        update_path "$file" "k8s/infrastructure/cert-manager" "k8s/infrastructure/02-network/cert-manager"
        log_success "$(basename "$file"): cert-manager パス更新"
    fi
done
echo ""

# 03-observability
log_info "【03-observability】パス更新"
find "${ARGOCD_APPS_DIR}" -name "*.yaml" -type f | while read -r file; do
    if grep -q "k8s/infrastructure/monitoring-config" "$file"; then
        update_path "$file" "k8s/infrastructure/monitoring-config" "k8s/infrastructure/03-observability/monitoring-config"
        log_success "$(basename "$file"): monitoring-config パス更新"
    fi
    if grep -q "k8s/infrastructure/monitoring-nodeports" "$file"; then
        update_path "$file" "k8s/infrastructure/monitoring-nodeports" "k8s/infrastructure/03-observability/monitoring-nodeports"
        log_success "$(basename "$file"): monitoring-nodeports パス更新"
    fi
    if grep -q "k8s/infrastructure/grafana" "$file"; then
        update_path "$file" "k8s/infrastructure/grafana" "k8s/infrastructure/03-observability/grafana"
        log_success "$(basename "$file"): grafana パス更新"
    fi
done
echo ""

# 04-ops
log_info "【04-ops】パス更新"
find "${ARGOCD_APPS_DIR}" -name "*.yaml" -type f | while read -r file; do
    if grep -q "k8s/infrastructure/atlantis" "$file"; then
        update_path "$file" "k8s/infrastructure/atlantis" "k8s/infrastructure/04-ops/atlantis"
        log_success "$(basename "$file"): atlantis パス更新"
    fi
    if grep -q "k8s/infrastructure/argocd" "$file"; then
        update_path "$file" "k8s/infrastructure/argocd" "k8s/infrastructure/04-ops/argocd"
        log_success "$(basename "$file"): argocd パス更新"
    fi
done
echo ""

log_success "パス更新完了！"
echo ""

# =============================================================================
# 検証
# =============================================================================

log_info "更新後のパスを検証中..."
echo ""

# 新しいパスが正しく設定されているか確認
log_info "新しいパス構造の確認:"
grep -r "path: k8s/infrastructure/" "${ARGOCD_APPS_DIR}/base" 2>/dev/null | grep -v "update_application_paths.sh" | sort | uniq || true
echo ""

log_success "検証完了"
echo ""
log_info "次のステップ:"
echo "  1. 変更を確認: git diff k8s/infrastructure/00-argocd-apps/"
echo "  2. Gitでコミット"
echo "  3. Terraform互換性確認"
echo "  4. make setup-all-vagrant で検証"
