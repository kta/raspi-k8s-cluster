# Terraform Infrastructure

Raspberry Pi Kubernetes クラスター向けのエンタープライズグレードな Terraform セットアップ。

## 📁 ディレクトリ構成

```
terraform/
├── modules/                    # 再利用可能なモジュール
│   ├── argocd/                 # ArgoCD デプロイメントモジュール
│   ├── sealed-secrets/         # Sealed Secrets コントローラー
│   └── atlantis-secrets/       # Atlantis GitHub 認証情報
├── environments/               # 環境固有の設定
│   ├── production/             # 本番環境
│   └── vagrant/                # 開発環境
└── README.md                   # このファイル

```

## 🏗️ アーキテクチャの原則

### 1. **モジュールファースト設計**

* 各コンポーネントは再利用可能なモジュールとする
* モジュールは環境に依存しない（Environment-agnostic）作り
* 明確な入出力（Input/Output）インターフェースを持つ

### 2. **環境の分離**

* 環境間を完全に隔離する
* 独立したステート（State）ファイルを持つ
* 環境固有の変数を使用する

### 3. **Infrastructure as Code (IaC) のベストプラクティス**

* DRY (Don't Repeat Yourself) 原則の遵守
* 適切な変数バリデーション
* 包括的な Output の定義
* 一貫した命名規則

### 4. **GitOps 対応**

* ArgoCD との統合
* ConfigMap による環境設定
* Sealed Secrets によるシークレット管理

## 🚀 クイックスタート

### 本番環境（Production）へのデプロイ

```bash
cd environments/production

# Terraform の初期化
terraform init

# 変更内容の確認
terraform plan

# インフラの適用
terraform apply

```

### Vagrant 環境へのデプロイ

```bash
cd environments/vagrant

terraform init
terraform apply

```

## 📋 モジュール・ドキュメント

各モジュールには独自の README が用意されており、以下が含まれています：

* 機能と能力
* 使用例
* 入力変数 (Inputs)
* 出力値 (Outputs)

### 利用可能なモジュール

* [ArgoCD](https://www.google.com/search?q=modules/argocd/README.md) - GitOps 継続的デリバリー
* [Sealed Secrets](https://www.google.com/search?q=modules/sealed-secrets/README.md) - シークレット管理
* [Atlantis Secrets](https://www.google.com/search?q=modules/atlantis-secrets/README.md) - GitHub 認証情報

## 🔧 設定

### 必須変数

環境ディレクトリ内に `terraform.tfvars` を作成してください：

```hcl
github_token    = "ghp_xxxxxxxxxxxxx"
github_username = "your-username"
github_repo_url = "https://github.com/your-username/your-repo.git"

```

### 自動生成される変数

ネットワーク設定は Ansible インベントリから自動生成されます：

* `environment`
* `metallb_ip_range`
* `ingress_ip`
* `vip`

再生成するには `make generate-tfvars ENV=production` を実行してください。

## 🔐 セキュリティのベストプラクティス

### シークレット管理

1. **Git にシークレットを絶対にコミットしない**
   - `terraform.tfvars` を `.gitignore` に追加する
   - 機密データは環境変数に保存する
   - Kubernetes シークレットには Sealed Secrets を使用する
2. **ステートファイルのセキュリティ**
   - リモートバックエンド（S3など）の検討
   - ステートの暗号化を有効化
   - ステートロックの実装

### リモートバックエンドの例

```hcl
terraform {
  backend "s3" {
    bucket         = "your-terraform-state"
    key            = "production/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-lock"
  }
}

```

## 📊 ステート管理

### ローカルステート（デフォルト）

ステートは各環境ディレクトリにローカル保存されます：

* `environments/production/terraform.tfstate`
* `environments/vagrant/terraform.tfstate`

### リモートステート（本番環境推奨）

`providers.tf` 内のバックエンド設定のコメントアウトを解除してください：

```hcl
terraform {
  backend "s3" {
    # ... 設定内容
  }
}

```

## 🔄 ワークフロー

### 初期セットアップ

```bash
# 1. ネットワーク設定の生成
make generate-tfvars ENV=production

# 2. 環境ディレクトリへ移動
cd terraform/environments/production

# 3. 設定例ファイルのコピー
cp terraform.tfvars.example terraform.tfvars

# 4. 値の編集
vim terraform.tfvars

# 5. 初期化と適用
terraform init
terraform apply

```

### 更新手順

```bash
# モジュールの更新
terraform get -update

# 変更内容の計画（Plan）
terraform plan

# 変更の適用（Apply）
terraform apply

```

### クリーンアップ（削除）

```bash
# インフラの破棄
terraform destroy

```

## 🔍 Outputs (出力)

デプロイ成功後、重要な情報が出力されます：

```bash
# すべての出力を表示
terraform output

# 特定の出力を表示
terraform output argocd_port_forward_command

```

## 🏷️ 命名規則

### リソース

* 分かりやすい名前を使用する
* パターン： `<タイプ>_<名前>`
* 例： `kubernetes_namespace_argocd`

### 変数

* スネークケース： `argocd_namespace`
* Boolean（真偽値）の接頭辞： `enable_ha`
* リスト型は複数形： `node_ips`

### モジュール

* ケバブケース： `argocd`, `sealed-secrets`
* 簡潔かつ説明的に

## 🧪 テスト

### 検証

```bash
# フォーマットチェック
terraform fmt -check -recursive

# 設定の検証
terraform validate

# 異なる tfvars での Plan 確認
terraform plan -var-file=test.tfvars

```

### モジュールテスト

```bash
# モジュールディレクトリへ移動
cd modules/argocd

# 初期化
terraform init

# 検証
terraform validate

```

## 🔧 トラブルシューティング

### よくある問題

**問題**: プロバイダの初期化に失敗する

```bash
# 解決策: プロバイダの更新
terraform init -upgrade

```

**問題**: モジュールが見つからない

```bash
# 解決策: モジュールのダウンロード
terraform get

```

**問題**: ステートロックエラー

```bash
# 解決策: 強制アンロック（注意して使用すること）
terraform force-unlock <LOCK_ID>

```

## 📖 追加リソース

* [Terraform Best Practices](https://www.terraform-best-practices.com/)
* [Kubernetes Provider Docs](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs)
* [Helm Provider Docs](https://registry.terraform.io/providers/hashicorp/helm/latest/docs)

## 🤝 貢献について (Contributing)

新しいモジュールを追加する場合：

1. 既存のモジュール構造に従うこと
2. 包括的な README を含めること
3. 適切な変数バリデーションを追加すること
4. すべての Output をドキュメント化すること
5. 両方の環境（Production/Vagrant）でテストすること

## 📝 メンテナンス

### バージョン更新

`versions.tf` 内のプロバイダバージョンを更新します：

```hcl
required_providers {
  kubernetes = {
    source  = "hashicorp/kubernetes"
    version = "~> 3.0"  # ここを更新
  }
}

```

### モジュール更新

環境ごとの `main.tf` 内でモジュールのバージョンを更新します：

```hcl
module "argocd" {
  source  = "../../modules/argocd"
  version = "1.0.0"  # 特定のバージョンに固定
  # ...
}

```