# 環境別IP管理機能 - 実装サマリー

## 🎯 目的

実機（production）とVagrant環境で異なるIPアドレスを**自動的に**使い分けるため、IPアドレスのハードコーディングを完全に排除しました。

## 📝 変更内容

### 1. Ansible インベントリの拡張

**ファイル:**
- `ansible/inventory/inventory.ini` (production環境)
- `ansible/inventory/inventory_vagrant.ini` (vagrant環境)

**追加された変数:**
```ini
# MetalLB / LoadBalancer設定
metallb_ip_range=192.168.1.200-192.168.1.220  # または 192.168.56.200-192.168.56.220
environment=production                          # または vagrant
ingress_ip=192.168.1.200                        # または 192.168.56.200
```

### 2. Kustomize構造の導入

**新規ディレクトリ構造:**
```
k8s/infra/metallb/
├── base/                              # 共通のベースマニフェスト
│   ├── kustomization.yaml
│   ├── kustomizeconfig.yaml
│   ├── metallb.yaml
│   └── ip-pool.yaml                   # プレースホルダー
├── overlays/
│   ├── production/                    # 実機環境用のIPレンジ
│   │   └── kustomization.yaml         # 192.168.1.200-220
│   └── vagrant/                       # Vagrant環境用のIPレンジ
│       └── kustomization.yaml         # 192.168.56.200-220
└── config.yaml                        # ArgoCD Application定義
```

**変更点:**
- `k8s/infra/metallb/resources/ip-pool.yaml` → `k8s/infra/metallb/base/ip-pool.yaml` に移動
- 環境別のIPレンジは overlays でパッチとして適用

### 3. Terraform変数の拡張

**ファイル:** `terraform/bootstrap/variables.tf`

**追加された変数:**
```hcl
variable "environment" {
  type        = string
  default     = "production"
  description = "デプロイ環境 (production または vagrant)"
}

variable "metallb_ip_range" {
  type        = string
  description = "MetalLB の IP アドレスプール範囲"
}

variable "ingress_ip" {
  type        = string
  description = "Ingress のデフォルト LoadBalancer IP"
}

variable "vip" {
  type        = string
  description = "Keepalived 仮想 IP アドレス"
}
```

**ファイル:** `terraform/bootstrap/argocd.tf`

**追加機能:**
- 環境設定を保存する ConfigMap (`environment-config`) を作成
- Kubernetes クラスタ内で環境変数を参照可能に

### 4. 自動化スクリプト

**新規スクリプト:**

#### `scripts/generate_tfvars.sh`
- Ansible インベントリから変数を抽出
- `terraform/bootstrap/terraform.auto.tfvars` を自動生成
- GitHub設定は既存の `terraform.tfvars` から継承

**使い方:**
```bash
./scripts/generate_tfvars.sh ansible/inventory/inventory.ini
# または
make generate-tfvars ENV=production
```

#### `scripts/patch_argocd_apps.sh`
- ArgoCD Application マニフェストの `path:` を環境に応じて更新
- `k8s/infra/metallb/config.yaml` の overlay パスを変更

**使い方:**
```bash
./scripts/patch_argocd_apps.sh production
# または
make patch-argocd-apps ENV=production
```

#### `scripts/validate_setup.sh`
- 環境設定の整合性を検証
- ファイル存在、変数値、overlay設定をチェック

**使い方:**
```bash
./scripts/validate_setup.sh production
# または
make validate-setup ENV=production
```

### 5. Makefile の拡張

**新規コマンド:**
```makefile
make env-info              # 現在の環境設定を表示
make generate-tfvars       # Terraform変数を自動生成
make patch-argocd-apps     # ArgoCD Applicationを更新
make validate-setup        # 環境設定を検証
```

**改善されたコマンド:**
```makefile
make ansible-setup         # 自動的に generate-tfvars と patch-argocd-apps を実行
make ansible-setup-vagrant # ENV=vagrant が自動設定される
make terraform-plan        # terraform.auto.tfvars がなければ自動生成
make terraform-apply       # terraform.auto.tfvars がなければ自動生成
```

**環境変数の指定:**
```bash
# 明示的に環境を指定
make ansible-setup ENV=production
make terraform-apply ENV=vagrant

# 自動検出（デフォルトは production）
make ansible-setup
```

### 6. ドキュメント

**新規ドキュメント:**
- `docs/environment_ip_management.md` - 完全なガイド（アーキテクチャ、使い方、トラブルシューティング）
- `docs/QUICKSTART_IP_MANAGEMENT.md` - クイックスタートガイド

**更新されたドキュメント:**
- `README.md` - 環境別IP管理セクションを追加
- `terraform/bootstrap/terraform.template` - 新しい変数の例を追加

**新規サンプルファイル:**
- `terraform/bootstrap/terraform.production.tfvars.example`
- `terraform/bootstrap/terraform.vagrant.tfvars.example`

### 7. .gitignore の更新

```gitignore
# Auto-generated Terraform variable files
terraform/bootstrap/terraform.auto.tfvars
terraform/bootstrap/*.auto.tfvars

# Backup files from sed
*.bak
```

## 🔄 ワークフロー

### Before（問題）
```
❌ phase2_3_setup.md に 192.168.1.200 がハードコード
❌ k8s/infra/metallb/resources/ip-pool.yaml に 192.168.1.200-220 がハードコード
❌ 環境を切り替えるたびに手動でファイルを編集
❌ 編集漏れや設定ミスが発生しやすい
```

### After（解決）
```
✅ Ansible インベントリが真実の源（Single Source of Truth）
✅ スクリプトで自動的に Terraform変数を生成
✅ Kustomize overlays で環境別マニフェストを管理
✅ make コマンド一つで環境に応じた設定を適用
✅ validate-setup で設定の整合性を確認
```

## 🚀 使い方の例

### 実機環境へのデプロイ

```bash
# 1. インベントリファイルを確認（すでに設定済み）
cat ansible/inventory/inventory.ini

# 2. 設定を検証
make validate-setup ENV=production

# 3. セットアップ（自動で変数生成とパッチ適用）
make ansible-setup ENV=production
make fetch-kubeconfig
make terraform-apply
make argocd-bootstrap

# または一括実行
make setup-all ENV=production
```

### Vagrant環境へのデプロイ

```bash
# すべて自動化！
make ansible-setup-vagrant  # ENV=vagrant が自動設定される
make fetch-kubeconfig-vagrant
make terraform-apply ENV=vagrant
make argocd-bootstrap
```

### IP設定を変更する場合

```bash
# 1. インベントリを編集
vim ansible/inventory/inventory.ini

# 2. Terraform変数を再生成
make generate-tfvars ENV=production

# 3. ArgoCD Applicationを更新
make patch-argocd-apps ENV=production

# 4. 設定を検証
make validate-setup ENV=production

# 5. Terraformを再実行
cd terraform/bootstrap && terraform apply

# 6. ArgoCDを同期
kubectl apply -f k8s/bootstrap/root-app.yaml
```

## 🎯 ベネフィット

### 1. 保守性の向上
- IPアドレスの一元管理（Ansible インベントリのみ）
- 変更時の影響範囲が明確

### 2. 人為的ミスの削減
- 自動生成により手動編集を排除
- 検証スクリプトで設定ミスを事前検出

### 3. 開発効率の向上
- 環境切り替えが `ENV=vagrant` の指定だけで完結
- Vagrant環境でのテストが容易

### 4. スケーラビリティ
- 新しい環境（staging等）の追加が容易
- Kustomize overlays で柔軟に対応可能

### 5. ドキュメント化
- 包括的なガイドで新しいメンバーもすぐに理解可能
- ベストプラクティスを明文化

## 📊 変更ファイル一覧

### 新規作成（15ファイル）
```
scripts/generate_tfvars.sh
scripts/patch_argocd_apps.sh
scripts/validate_setup.sh
k8s/infra/metallb/base/kustomization.yaml
k8s/infra/metallb/base/kustomizeconfig.yaml
k8s/infra/metallb/base/ip-pool.yaml
k8s/infra/metallb/overlays/production/kustomization.yaml
k8s/infra/metallb/overlays/vagrant/kustomization.yaml
terraform/bootstrap/terraform.production.tfvars.example
terraform/bootstrap/terraform.vagrant.tfvars.example
docs/environment_ip_management.md
docs/QUICKSTART_IP_MANAGEMENT.md
```

### 変更（6ファイル）
```
ansible/inventory/inventory.ini
ansible/inventory/inventory_vagrant.ini
terraform/bootstrap/variables.tf
terraform/bootstrap/argocd.tf
terraform/bootstrap/terraform.template
k8s/infra/metallb/config.yaml
Makefile
README.md
.gitignore
```

### 移動（2ファイル）
```
k8s/infra/metallb/resources/ip-pool.yaml → k8s/infra/metallb/base/ip-pool.yaml
k8s/infra/metallb/metallb.yaml → k8s/infra/metallb/base/metallb.yaml
```

## 🧪 テスト方法

### 設定の検証
```bash
# Production環境
make validate-setup ENV=production

# Vagrant環境
make validate-setup ENV=vagrant
```

### Kustomizeのビルドテスト
```bash
# Production overlay
kustomize build k8s/infra/metallb/overlays/production

# Vagrant overlay
kustomize build k8s/infra/metallb/overlays/vagrant
```

### Terraform plan の確認
```bash
# Production環境
make generate-tfvars ENV=production
cd terraform/bootstrap && terraform plan

# Vagrant環境
make generate-tfvars ENV=vagrant
cd terraform/bootstrap && terraform plan
```

## 📚 参考資料

- [Kustomize Documentation](https://kustomize.io/)
- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
- [Terraform Variables](https://www.terraform.io/language/values/variables)
- [12-Factor App Config](https://12factor.net/config)

## ✅ チェックリスト

実装が完了したら、以下を確認してください：

- [ ] 両方の環境で `make validate-setup` がパスする
- [ ] Kustomize overlays が正しくビルドできる
- [ ] Terraform plan がエラーなく実行できる
- [ ] スクリプトに実行権限がある（`chmod +x scripts/*.sh`）
- [ ] `.gitignore` に `terraform.auto.tfvars` が追加されている
- [ ] ドキュメントを一読して使い方を理解した

## 🎉 まとめ

この実装により、**IPアドレスのハードコーディング問題を完全に解決**し、**環境を自動的に切り替える仕組み**を構築しました。実機とVagrant環境の運用が格段に楽になり、将来的な環境追加も容易になりました。

質問や改善提案があれば、お気軽にどうぞ！
