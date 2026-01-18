# Terraform環境検証機能 - 実装ガイド

## 🎯 解決した問題

**ユーザーからの指摘:**
> `make terraform-apply` を実行すると、`terraform.auto.tfvars` は常に production 環境の設定で生成されるのでは？

**問題:**
```bash
# Vagrant環境で terraform-apply を実行しても...
make terraform-apply

# terraform.auto.tfvars には production の設定が生成されてしまう
# environment = "production"
# metallb_ip_range = "192.168.1.200-192.168.1.220"
```

❌ 環境の不一致が発生  
❌ Vagrant環境に production の IP が適用される  
❌ 気づかずにデプロイしてしまう危険性  

## ✅ 解決策

**自動環境検証を実装:**
```bash
# 環境を明示的に指定
make terraform-apply ENV=vagrant

# 自動で以下を実行:
# 1. terraform.auto.tfvars の環境をチェック
# 2. 不一致なら自動的に再生成
# 3. 正しい環境の設定で terraform apply
```

✅ 環境の自動検証  
✅ 不一致時の自動修正  
✅ 安全なデプロイ  

---

## 📦 実装内容

### 1. 環境検証スクリプト

**`scripts/verify_tfvars_environment.sh`**

```bash
#!/bin/bash
# terraform.auto.tfvars の環境が期待する環境と一致するかを検証

EXPECTED_ENV="${1:-production}"
TFVARS_FILE="terraform/bootstrap/terraform.auto.tfvars"

# 環境を抽出
ACTUAL_ENV=$(grep "^environment" "$TFVARS_FILE" | cut -d'=' -f2 | tr -d ' "')

# 環境が一致するかチェック
if [[ "$ACTUAL_ENV" != "$EXPECTED_ENV" ]]; then
  echo "❌ エラー: 環境が一致しません"
  echo "  期待: $EXPECTED_ENV"
  echo "  実際: $ACTUAL_ENV"
  exit 1
fi

echo "✅ 環境が一致しています: $EXPECTED_ENV"
```

### 2. Makefile の改善

**Before:**
```makefile
.PHONY: terraform-apply
terraform-apply:
	@if [ ! -f terraform/bootstrap/terraform.auto.tfvars ]; then \
		$(MAKE) generate-tfvars; \  # 常に production が生成される！
	fi
	cd terraform/bootstrap && terraform apply
```

**After:**
```makefile
.PHONY: terraform-apply
terraform-apply:
	@if [ ! -f terraform/bootstrap/terraform.auto.tfvars ]; then \
		$(MAKE) generate-tfvars ENV=$(ENVIRONMENT); \  # 環境を指定
	else \
		./scripts/verify_tfvars_environment.sh $(ENVIRONMENT) || \
		(echo "再生成中..." && $(MAKE) generate-tfvars ENV=$(ENVIRONMENT)); \
	fi
	cd terraform/bootstrap && terraform apply
```

### 3. 専用コマンドの追加

```makefile
.PHONY: terraform-apply-vagrant
terraform-apply-vagrant: ## Vagrant環境でTerraformを適用
	$(MAKE) terraform-apply ENV=vagrant
```

---

## 🚀 使い方

### Production環境

```bash
# 明示的に環境を指定（推奨）
make terraform-apply ENV=production

# または省略（デフォルトは production）
make terraform-apply
```

### Vagrant環境

```bash
# 明示的に環境を指定
make terraform-apply ENV=vagrant

# または専用コマンド
make terraform-apply-vagrant
```

---

## 🔍 動作例

### ケース1: tfvars が存在しない場合

```bash
$ make terraform-apply ENV=vagrant

⚠️  terraform.auto.tfvars が見つかりません。生成します...
🔄 Terraform変数を生成中 (環境: vagrant)...
✅ Terraform変数ファイルを生成しました

# Terraform apply を実行...
```

### ケース2: 正しい環境の tfvars が存在する場合

```bash
$ make terraform-apply ENV=vagrant

✅ 環境が一致しています: vagrant
📋 設定:
  環境: vagrant
  MetalLB IP範囲: 192.168.56.200-192.168.56.220
  Ingress IP: 192.168.56.200

# Terraform apply を実行...
```

### ケース3: 環境が不一致の場合

```bash
$ make terraform-apply ENV=vagrant

❌ エラー: 環境が一致しません
  期待: vagrant
  実際: production

再生成中...
🔄 Terraform変数を生成中 (環境: vagrant)...
✅ Terraform変数ファイルを生成しました

# 正しい環境で Terraform apply を実行...
```

---

## 📊 検証フロー

```
make terraform-apply ENV=vagrant
          │
          ▼
terraform.auto.tfvars
    存在する？
          │
    ┌─────┴─────┐
    NO          YES
    │            │
    ▼            ▼
generate     verify_environment
  tfvars        vagrant == vagrant?
    │            │
    │       ┌────┴────┐
    │       NO       YES
    │       │         │
    │   regenerate    │
    │     tfvars      │
    │       │         │
    └───────┴─────────┘
            │
            ▼
     terraform apply
```

---

## 🧪 テスト方法

### 環境検証のテスト

```bash
# Production 環境を生成
make generate-tfvars ENV=production

# Vagrant 環境として検証（失敗するはず）
./scripts/verify_tfvars_environment.sh vagrant
# ❌ エラー: 環境が一致しません
#   期待: vagrant
#   実際: production

# Production 環境として検証（成功するはず）
./scripts/verify_tfvars_environment.sh production
# ✅ 環境が一致しています: production
```

### 自動修正のテスト

```bash
# Production 環境の tfvars を生成
make generate-tfvars ENV=production

# Vagrant 環境として terraform-apply（自動的に再生成される）
make terraform-apply ENV=vagrant
# ❌ エラー: 環境が一致しません
# 再生成中...
# ✅ Terraform変数ファイルを生成しました
```

---

## 📝 ベストプラクティス

### ✅ 推奨

1. **常に ENV を明示的に指定**
   ```bash
   make terraform-apply ENV=production
   make terraform-apply ENV=vagrant
   ```

2. **デプロイ前に検証**
   ```bash
   make validate-setup ENV=production
   make terraform-apply ENV=production
   ```

3. **専用コマンドを使用**
   ```bash
   make terraform-apply-vagrant
   ```

### ❌ 非推奨

1. **ENV を省略（デフォルトに依存）**
   ```bash
   make terraform-apply  # production になる
   ```

2. **手動で tfvars を編集**
   ```bash
   vim terraform/bootstrap/terraform.auto.tfvars
   # 自動生成ファイルなので上書きされる
   ```

---

## 🛠️ トラブルシューティング

### 問題: 環境が一致しないエラーが出る

```bash
❌ エラー: 環境が一致しません
  期待: vagrant
  実際: production
```

**解決策:**
```bash
# tfvars を削除して再生成
rm terraform/bootstrap/terraform.auto.tfvars
make generate-tfvars ENV=vagrant

# または自動修正を利用
make terraform-apply ENV=vagrant
```

### 問題: tfvars が生成されない

```bash
⚠️  terraform.auto.tfvars が見つかりません。生成します...
❌ エラー: インベントリファイルが見つかりません
```

**解決策:**
```bash
# インベントリファイルを確認
ls -la ansible/inventory/

# 環境変数が正しいか確認
make env-info ENV=vagrant
```

---

## ✅ まとめ

**指摘された問題を完全に解決しました！**

| 改善点 | 実装 |
|--------|------|
| 環境の自動検証 | `verify_tfvars_environment.sh` |
| 不一致時の自動修正 | Makefile の条件分岐 |
| Vagrant専用コマンド | `make terraform-apply-vagrant` |
| ENV変数の適切な伝播 | `$(ENVIRONMENT)` の使用 |

**これで安心して環境ごとにデプロイできます！** ✨

次のステップ:
```bash
# 環境を確認
make env-info ENV=vagrant

# 設定を検証
make validate-setup ENV=vagrant

# 安全にデプロイ
make terraform-apply ENV=vagrant
```
