#!/bin/bash
# Ansible インベントリから環境変数を抽出してTerraform用tfvarsファイルを生成
#
# 使い方:
#   ./generate_tfvars.sh [inventory_file] [output_file]
#
# 例:
#   ./generate_tfvars.sh ansible/inventory/inventory.ini terraform/bootstrap/terraform.auto.tfvars
#   ./generate_tfvars.sh ansible/inventory/inventory_vagrant.ini terraform/bootstrap/terraform.auto.tfvars

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# デフォルト値
INVENTORY_FILE="${1:-$PROJECT_ROOT/ansible/inventory/inventory.ini}"
OUTPUT_FILE="${2:-$PROJECT_ROOT/terraform/bootstrap/terraform.auto.tfvars}"

if [[ ! -f "$INVENTORY_FILE" ]]; then
	echo "❌ エラー: インベントリファイルが見つかりません: $INVENTORY_FILE"
	exit 1
fi

echo "📋 インベントリファイルを読み込み中: $INVENTORY_FILE"

# Ansibleインベントリから変数を抽出
extract_var() {
	local var_name="$1"
	grep "^${var_name}=" "$INVENTORY_FILE" | head -1 | cut -d'=' -f2 | tr -d ' '
}

ENVIRONMENT=$(extract_var "environment")
METALLB_IP_RANGE=$(extract_var "metallb_ip_range")
INGRESS_IP=$(extract_var "ingress_ip")
VIP=$(extract_var "vip")

# 既存のterraform.tfvarsからGitHub設定を読み取る（存在する場合）
GITHUB_USERNAME=""
GITHUB_TOKEN=""
GITHUB_REPO_URL=""

TFVARS_FILE="$PROJECT_ROOT/terraform/bootstrap/terraform.tfvars"
if [[ -f "$TFVARS_FILE" ]]; then
	echo "📄 既存のterraform.tfvarsからGitHub設定を読み込み中..."
	GITHUB_USERNAME=$(grep '^github_username' "$TFVARS_FILE" | cut -d'=' -f2 | tr -d ' "')
	GITHUB_TOKEN=$(grep '^github_token' "$TFVARS_FILE" | cut -d'=' -f2 | tr -d ' "')
	GITHUB_REPO_URL=$(grep '^github_repo_url' "$TFVARS_FILE" | cut -d'=' -f2 | tr -d ' "')
fi

# デフォルト値を設定
GITHUB_USERNAME="${GITHUB_USERNAME:-kta}"
GITHUB_TOKEN="${GITHUB_TOKEN:-ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx}"
GITHUB_REPO_URL="${GITHUB_REPO_URL:-https://github.com/kta/raspi-k8s-cluster.git}"

# tfvars ファイルを生成
cat >"$OUTPUT_FILE" <<EOF
# 自動生成されたファイル
# 生成元: $INVENTORY_FILE
# 生成日時: $(date '+%Y-%m-%d %H:%M:%S')

# GitHub設定
github_username = "$GITHUB_USERNAME"
github_token    = "$GITHUB_TOKEN"
github_repo_url = "$GITHUB_REPO_URL"

# 環境設定
environment      = "$ENVIRONMENT"
metallb_ip_range = "$METALLB_IP_RANGE"
ingress_ip       = "$INGRESS_IP"
vip              = "$VIP"
EOF

echo "✅ Terraform変数ファイルを生成しました: $OUTPUT_FILE"
echo ""
echo "📝 内容:"
cat "$OUTPUT_FILE"
echo ""
echo "💡 ヒント: GitHub設定が正しくない場合は、$TFVARS_FILE を編集してから再実行してください"
