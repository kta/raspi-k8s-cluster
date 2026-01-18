#!/bin/bash
# terraform.auto.tfvars の環境が期待する環境と一致するかを検証
#
# 使い方:
#   ./verify_tfvars_environment.sh [expected_environment]
#
# 例:
#   ./verify_tfvars_environment.sh production
#   ./verify_tfvars_environment.sh vagrant

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

EXPECTED_ENV="${1:-production}"

if [[ "$EXPECTED_ENV" != "production" && "$EXPECTED_ENV" != "vagrant" ]]; then
  echo "❌ エラー: environment は production または vagrant である必要があります"
  exit 1
fi

TFVARS_FILE="$PROJECT_ROOT/terraform/bootstrap/terraform.auto.tfvars"

# ファイルが存在しない場合
if [[ ! -f "$TFVARS_FILE" ]]; then
  echo "⚠️  terraform.auto.tfvars が見つかりません"
  echo "生成が必要です: make generate-tfvars ENV=$EXPECTED_ENV"
  exit 2
fi

# 環境を抽出
ACTUAL_ENV=$(grep "^environment" "$TFVARS_FILE" | cut -d'=' -f2 | tr -d ' "')

if [[ -z "$ACTUAL_ENV" ]]; then
  echo "❌ エラー: terraform.auto.tfvars に environment が設定されていません"
  echo "再生成が必要です: make generate-tfvars ENV=$EXPECTED_ENV"
  exit 1
fi

# 環境が一致するかチェック
if [[ "$ACTUAL_ENV" != "$EXPECTED_ENV" ]]; then
  echo "❌ エラー: 環境が一致しません"
  echo "  期待: $EXPECTED_ENV"
  echo "  実際: $ACTUAL_ENV"
  echo ""
  echo "修正方法:"
  echo "  1. 正しい環境の tfvars を生成"
  echo "     make generate-tfvars ENV=$EXPECTED_ENV"
  echo ""
  echo "  2. または、既存の tfvars を削除して再生成"
  echo "     rm $TFVARS_FILE"
  echo "     make terraform-apply ENV=$EXPECTED_ENV"
  exit 1
fi

# 一致している場合
echo "✅ 環境が一致しています: $EXPECTED_ENV"

# 追加で IP アドレスも表示
METALLB_IP=$(grep "^metallb_ip_range" "$TFVARS_FILE" | cut -d'=' -f2 | tr -d ' "')
INGRESS_IP=$(grep "^ingress_ip" "$TFVARS_FILE" | cut -d'=' -f2 | tr -d ' "')
VIP=$(grep "^vip" "$TFVARS_FILE" | cut -d'=' -f2 | tr -d ' "')

echo "📋 設定:"
echo "  環境: $ACTUAL_ENV"
echo "  MetalLB IP範囲: $METALLB_IP"
echo "  Ingress IP: $INGRESS_IP"
echo "  VIP: $VIP"

exit 0
