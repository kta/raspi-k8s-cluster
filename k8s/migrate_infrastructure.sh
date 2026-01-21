#!/usr/bin/env bash
# =============================================================================
# Infrastructure Migration Script
# =============================================================================
# このスクリプトは k8s/infrastructure/ を新しいレイヤー構造に再編成します
#
# 使用方法:
#   bash migrate_infrastructure.sh [--dry-run]
#
# オプション:
#   --dry-run    実際の移動を行わず、何が移動されるかを表示
#
# =============================================================================

set -euo pipefail

# カラー出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# スクリプトのディレクトリ
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${SCRIPT_DIR}/infrastructure"

# ドライランモード
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo -e "${YELLOW}🔍 ドライランモード: 実際の変更は行いません${NC}"
    echo ""
fi

# バックアップディレクトリ
BACKUP_DIR="${SCRIPT_DIR}/.migration_backup_$(date +%Y%m%d_%H%M%S)"

# =============================================================================
# ヘルパー関数
# =============================================================================

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# ディレクトリ移動関数
move_dir() {
    local src="$1"
    local dest="$2"
    local description="$3"

    if [[ ! -d "${src}" ]]; then
        log_warning "${description}: ソースディレクトリが存在しません - ${src}"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "  [DRY-RUN] ${src} → ${dest}"
        return 0
    fi

    log_info "${description}: ${src} → ${dest}"
    
    # 親ディレクトリを作成
    mkdir -p "$(dirname "${dest}")"
    
    # 移動
    mv "${src}" "${dest}"
    
    log_success "${description}: 移動完了"
}

# =============================================================================
# 事前チェック
# =============================================================================

log_info "事前チェックを実行中..."

if [[ ! -d "${INFRA_DIR}" ]]; then
    log_error "infrastructure ディレクトリが見つかりません: ${INFRA_DIR}"
    exit 1
fi

# 既存のレイヤーディレクトリが存在する場合は警告
for layer in "00-argocd-apps" "01-system" "02-network" "03-observability" "04-ops"; do
    if [[ -d "${INFRA_DIR}/${layer}" ]]; then
        log_error "レイヤーディレクトリが既に存在します: ${layer}"
        log_error "移行は既に実行されている可能性があります"
        exit 1
    fi
done

log_success "事前チェック完了"
echo ""

# =============================================================================
# バックアップ作成
# =============================================================================

if [[ "${DRY_RUN}" == "false" ]]; then
    log_info "バックアップを作成中: ${BACKUP_DIR}"
    mkdir -p "${BACKUP_DIR}"
    
    # infrastructure ディレクトリ全体をバックアップ
    cp -r "${INFRA_DIR}" "${BACKUP_DIR}/"
    
    log_success "バックアップ作成完了"
    echo ""
fi

# =============================================================================
# レイヤーディレクトリ作成
# =============================================================================

log_info "レイヤーディレクトリを作成中..."

LAYERS=(
    "00-argocd-apps"
    "01-system"
    "02-network"
    "03-observability"
    "04-ops"
)

if [[ "${DRY_RUN}" == "false" ]]; then
    for layer in "${LAYERS[@]}"; do
        mkdir -p "${INFRA_DIR}/${layer}"
        log_success "作成: ${layer}"
    done
else
    for layer in "${LAYERS[@]}"; do
        echo "  [DRY-RUN] 作成予定: ${layer}"
    done
fi

echo ""

# =============================================================================
# コンポーネント移動
# =============================================================================

log_info "コンポーネントを移動中..."
echo ""

# 00-argocd-apps: Control Plane
log_info "【00-argocd-apps】Control Plane コンポーネント"
move_dir "${INFRA_DIR}/argocd-apps" "${INFRA_DIR}/00-argocd-apps/argocd-apps" "argocd-apps"
echo ""

# 01-system: Core System
log_info "【01-system】Core System コンポーネント"
move_dir "${INFRA_DIR}/cni" "${INFRA_DIR}/01-system/cni" "CNI"
# sealed-secrets は存在しない可能性があるため警告のみ
if [[ -d "${INFRA_DIR}/sealed-secrets" ]]; then
    move_dir "${INFRA_DIR}/sealed-secrets" "${INFRA_DIR}/01-system/sealed-secrets" "Sealed Secrets"
else
    log_warning "sealed-secrets ディレクトリが見つかりません（スキップ）"
fi
echo ""

# 02-network: Network & Ingress
log_info "【02-network】Network & Ingress コンポーネント"
move_dir "${INFRA_DIR}/metallb" "${INFRA_DIR}/02-network/metallb" "MetalLB"
move_dir "${INFRA_DIR}/traefik" "${INFRA_DIR}/02-network/traefik" "Traefik"
move_dir "${INFRA_DIR}/cert-manager" "${INFRA_DIR}/02-network/cert-manager" "Cert Manager"
move_dir "${INFRA_DIR}/cert-manager-resources" "${INFRA_DIR}/02-network/cert-manager-resources" "Cert Manager Resources"
echo ""

# 03-observability: Observability & Monitoring
log_info "【03-observability】Observability & Monitoring コンポーネント"
if [[ -d "${INFRA_DIR}/kube-prometheus-stack" ]]; then
    move_dir "${INFRA_DIR}/kube-prometheus-stack" "${INFRA_DIR}/03-observability/kube-prometheus-stack" "Kube Prometheus Stack"
else
    log_warning "kube-prometheus-stack ディレクトリが見つかりません（スキップ）"
fi
move_dir "${INFRA_DIR}/monitoring-config" "${INFRA_DIR}/03-observability/monitoring-config" "Monitoring Config"
move_dir "${INFRA_DIR}/monitoring-nodeports" "${INFRA_DIR}/03-observability/monitoring-nodeports" "Monitoring NodePorts"
move_dir "${INFRA_DIR}/grafana" "${INFRA_DIR}/03-observability/grafana" "Grafana"
echo ""

# 04-ops: Operations Tools
log_info "【04-ops】Operations Tools コンポーネント"
move_dir "${INFRA_DIR}/atlantis" "${INFRA_DIR}/04-ops/atlantis" "Atlantis"
move_dir "${INFRA_DIR}/argocd" "${INFRA_DIR}/04-ops/argocd" "ArgoCD"
echo ""

# =============================================================================
# 完了メッセージ
# =============================================================================

if [[ "${DRY_RUN}" == "true" ]]; then
    echo ""
    log_success "ドライラン完了"
    echo ""
    log_info "実際に移行を実行するには、--dry-run オプションなしで実行してください:"
    echo "  bash migrate_infrastructure.sh"
else
    echo ""
    log_success "移行完了！"
    echo ""
    log_info "バックアップ: ${BACKUP_DIR}"
    log_info "問題が発生した場合は、以下のコマンドでロールバックできます:"
    echo "  rm -rf ${INFRA_DIR}"
    echo "  mv ${BACKUP_DIR}/infrastructure ${INFRA_DIR}"
    echo ""
    log_info "次のステップ:"
    echo "  1. 変更を確認: ls -la ${INFRA_DIR}"
    echo "  2. Git で変更をコミット"
    echo "  3. bootstrap/root.yaml を更新"
    echo "  4. make setup-all-vagrant で検証"
fi
