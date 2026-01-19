#!/bin/bash
# 環境別IP管理の設定を検証するスクリプト
#
# 使い方:
#   ./validate_setup.sh [environment]
#
# 例:
#   ./validate_setup.sh production
#   ./validate_setup.sh vagrant

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENVIRONMENT="${1:-production}"

if [[ "$ENVIRONMENT" != "production" && "$ENVIRONMENT" != "vagrant" ]]; then
	echo "❌ エラー: environment は production または vagrant である必要があります"
	exit 1
fi

echo "🔍 環境 '$ENVIRONMENT' の設定を検証中..."
echo ""

# カラーコード
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0

# チェック関数
check_file() {
	local file="$1"
	local description="$2"

	if [[ -f "$file" ]]; then
		echo -e "${GREEN}✓${NC} $description: $file"
		return 0
	else
		echo -e "${RED}✗${NC} $description が見つかりません: $file"
		ERRORS=$((ERRORS + 1))
		return 1
	fi
}

check_value() {
	local actual="$1"
	local expected="$2"
	local description="$3"

	if [[ "$actual" == "$expected" ]]; then
		echo -e "${GREEN}✓${NC} $description: $actual"
		return 0
	else
		echo -e "${RED}✗${NC} $description が一致しません"
		echo -e "  期待値: $expected"
		echo -e "  実際値: $actual"
		ERRORS=$((ERRORS + 1))
		return 1
	fi
}

# 環境別の期待値
if [[ "$ENVIRONMENT" == "production" ]]; then
	EXPECTED_METALLB_RANGE="192.168.1.200-192.168.1.220"
	EXPECTED_INGRESS_IP="192.168.1.200"
	EXPECTED_VIP="192.168.1.100"
	INVENTORY_FILE="$PROJECT_ROOT/ansible/inventory/inventory.ini"
else
	EXPECTED_METALLB_RANGE="192.168.56.200-192.168.56.220"
	EXPECTED_INGRESS_IP="192.168.56.200"
	EXPECTED_VIP="192.168.56.100"
	INVENTORY_FILE="$PROJECT_ROOT/ansible/inventory/inventory_vagrant.ini"
fi

echo "=== ファイル存在チェック ==="
check_file "$INVENTORY_FILE" "Ansible インベントリファイル"
check_file "$PROJECT_ROOT/k8s/infra/metallb/base/kustomization.yaml" "MetalLB base kustomization"
check_file "$PROJECT_ROOT/k8s/infra/metallb/overlays/production/kustomization.yaml" "MetalLB production overlay"
check_file "$PROJECT_ROOT/k8s/infra/metallb/overlays/vagrant/kustomization.yaml" "MetalLB vagrant overlay"
check_file "$PROJECT_ROOT/scripts/generate_tfvars.sh" "tfvars生成スクリプト"
check_file "$PROJECT_ROOT/k8s/bootstrap/root.yaml" "ApplicationSet定義"
echo ""

echo "=== Ansible インベントリ値チェック ==="
if [[ -f "$INVENTORY_FILE" ]]; then
	ACTUAL_METALLB_RANGE=$(grep "^metallb_ip_range=" "$INVENTORY_FILE" | cut -d'=' -f2 | tr -d ' ')
	ACTUAL_INGRESS_IP=$(grep "^ingress_ip=" "$INVENTORY_FILE" | cut -d'=' -f2 | tr -d ' ')
	ACTUAL_VIP=$(grep "^vip=" "$INVENTORY_FILE" | cut -d'=' -f2 | tr -d ' ')
	ACTUAL_ENV=$(grep "^cluster_env=" "$INVENTORY_FILE" | cut -d'=' -f2 | tr -d ' ')

	check_value "$ACTUAL_ENV" "$ENVIRONMENT" "cluster_env"
	check_value "$ACTUAL_METALLB_RANGE" "$EXPECTED_METALLB_RANGE" "metallb_ip_range"
	check_value "$ACTUAL_INGRESS_IP" "$EXPECTED_INGRESS_IP" "ingress_ip"
	check_value "$ACTUAL_VIP" "$EXPECTED_VIP" "vip"
fi
echo ""

echo "=== Kustomize overlay チェック ==="
OVERLAY_FILE="$PROJECT_ROOT/k8s/infra/metallb/overlays/$ENVIRONMENT/kustomization.yaml"
if [[ -f "$OVERLAY_FILE" ]]; then
	OVERLAY_IP=$(grep "value:" "$OVERLAY_FILE" | awk '{print $2}' | tr -d '"')
	check_value "$OVERLAY_IP" "$EXPECTED_METALLB_RANGE" "Kustomize overlay IPレンジ"
else
	echo -e "${RED}✗${NC} Overlay ファイルが見つかりません: $OVERLAY_FILE"
	ERRORS=$((ERRORS + 1))
fi
echo ""

echo "=== ArgoCD Application チェック ==="
ARGOCD_CONFIG="$PROJECT_ROOT/k8s/infra/metallb/config.yaml"
if [[ -f "$ARGOCD_CONFIG" ]]; then
	ARGOCD_PATH=$(grep "path: k8s/infra/metallb/overlays" "$ARGOCD_CONFIG" | awk '{print $2}')
	EXPECTED_PATH="k8s/infra/metallb/overlays/$ENVIRONMENT"

	if [[ -n "$ARGOCD_PATH" ]]; then
		check_value "$ARGOCD_PATH" "$EXPECTED_PATH" "ArgoCD Application path"
	else
		echo -e "${YELLOW}⚠${NC}  ArgoCD Application path が設定されていません（手動設定が必要）"
	fi
fi
echo ""

echo "=== Terraform変数ファイル チェック ==="
TFVARS_FILE="$PROJECT_ROOT/terraform/bootstrap/terraform.auto.tfvars"
if [[ -f "$TFVARS_FILE" ]]; then
	echo -e "${GREEN}✓${NC} terraform.auto.tfvars が存在します"

	TF_ENV=$(grep "^environment" "$TFVARS_FILE" | cut -d'=' -f2 | tr -d ' "')
	TF_METALLB=$(grep "^metallb_ip_range" "$TFVARS_FILE" | cut -d'=' -f2 | tr -d ' "')

	if [[ -n "$TF_ENV" ]]; then
		check_value "$TF_ENV" "$ENVIRONMENT" "Terraform environment"
	fi

	if [[ -n "$TF_METALLB" ]]; then
		check_value "$TF_METALLB" "$EXPECTED_METALLB_RANGE" "Terraform metallb_ip_range"
	fi
else
	echo -e "${YELLOW}⚠${NC}  terraform.auto.tfvars が存在しません（make generate-tfvars で生成してください）"
fi
echo ""

echo "=== スクリプト実行権限チェック ==="
for script in generate_tfvars.sh validate_setup.sh; do
	script_path="$PROJECT_ROOT/scripts/$script"
	if [[ -x "$script_path" ]]; then
		echo -e "${GREEN}✓${NC} $script は実行可能です"
	else
		echo -e "${RED}✗${NC} $script に実行権限がありません"
		ERRORS=$((ERRORS + 1))
	fi
done
echo ""

# 結果サマリー
echo "========================================"
if [[ $ERRORS -eq 0 ]]; then
	echo -e "${GREEN}✅ すべてのチェックに合格しました！${NC}"
	echo ""
	echo "次のステップ:"
	echo "  1. make ansible-setup ENV=$ENVIRONMENT"
	echo "  2. make terraform-apply"
	echo "  3. make argocd-bootstrap"
	exit 0
else
	echo -e "${RED}❌ $ERRORS 件のエラーが見つかりました${NC}"
	echo ""
	echo "修正方法:"
	echo "  1. ansible/inventory/inventory*.ini を確認"
	echo "  2. make generate-tfvars ENV=$ENVIRONMENT を実行"
	exit 1
fi
