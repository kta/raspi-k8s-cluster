# GitHub Actions ワークフロー

このディレクトリには、プロジェクトの CI/CD パイプラインが含まれています。

## ワークフロー一覧

### 1. Terraform CI (`terraform-ci.yaml`)
**トリガー:** PR作成/更新、mainブランチへのpush

**実行内容:**
- `terraform fmt` - コードフォーマットチェック
- `terraform init` - 初期化
- `terraform validate` - 構文検証
- `tflint` - Lintチェック（再帰的）
- `tfsec` - セキュリティスキャン（SARIF形式）
- ドキュメント存在確認
- ArgoCD マニフェスト検証
- Atlantis 設定ファイル検証

**必須チェック:** fmt, validate が成功すること

### 2. PR Auto Labeler (`pr-labeler.yaml`)
**トリガー:** PR作成/更新

**実行内容:**
変更されたファイルのパスに基づいて自動でラベルを付与

- `terraform/` → `terraform` ラベル
- `terraform/modules/vm/` → `module:vm` ラベル
- `terraform/modules/kubernetes/` → `module:kubernetes` ラベル
- `terraform/modules/argocd/` → `module:argocd` ラベル
- `templates/` → `cloud-init` ラベル
- `docs/`, `README.md` → `documentation` ラベル
- `argocd-apps/` → `argocd` ラベル
- `.github/workflows/` → `ci/cd` ラベル
- `atlantis.yaml` → `atlantis` ラベル

### 3. Release (`release.yaml`)
**トリガー:** `v*.*.*` 形式のタグ作成時

**実行内容:**
- 変更履歴の自動生成
- Terraform設定ファイルのアーカイブ作成
- ドキュメントのアーカイブ作成
- GitHub Release の作成と成果物の添付

**成果物:**
- `terraform-config.tar.gz` - Terraform設定一式
- `documentation.tar.gz` - ドキュメント一式

## ローカルでの実行

### Terraform チェックを手動実行
```bash
cd terraform

# フォーマットチェック
terraform fmt -check -recursive

# 初期化
terraform init -backend=false

# 検証
terraform validate

# Lint
tflint --init
tflint --recursive

# セキュリティスキャン
tfsec .
```

### ArgoCD マニフェスト検証
```bash
kubectl --dry-run=client apply -f argocd-apps/app-of-apps.yaml
kubectl --dry-run=client apply -f argocd-apps/bootstrap/
kubectl --dry-run=client apply -f argocd-apps/applications/
```

## トラブルシューティング

### Terraform CI が失敗する場合

**fmt エラー:**
```bash
terraform fmt -recursive
git add .
git commit -m "chore: format terraform files"
```

**validate エラー:**
- エラーメッセージを確認し、該当ファイルを修正
- モジュール参照やリソース定義のミスが多い

**tflint 警告:**
- `.tflint.hcl` のルール設定を確認
- 未使用変数やリソースを削除

**tfsec 警告:**
- セキュリティリスクを確認し、必要に応じて修正
- 誤検知の場合は `tfsec:ignore` コメントで除外可能

### ラベルが自動付与されない場合

1. GitHub Token の権限確認（`pull-requests: write` 必要）
2. ワークフローログでエラーメッセージを確認
3. 新しいラベルを手動で作成してから再実行

### Release が作成されない場合

1. タグ形式が `v*.*.*` であることを確認
2. GitHub Token の権限確認（`contents: write` 必要）
3. ワークフローログでアーカイブ作成エラーを確認

## Dependabot

`.github/dependabot.yaml` により以下が自動更新されます:

- **GitHub Actions** - 毎週月曜 9:00 (JST)
- **Terraform Providers** - 毎週月曜 9:00 (JST)
- **Docker Images** - 毎週月曜 9:00 (JST)

**注意:** Proxmox Provider のメジャーバージョンアップは手動確認を推奨
