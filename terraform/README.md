# Terraform Directory - Phase 2 & 4: インフラ & Bootstrap

このディレクトリには、Kubernetesクラスター上のインフラストラクチャコンポーネントとBootstrapツールのTerraformコードが含まれています。

## ディレクトリ構造

```
terraform/
├── bootstrap/                 # ArgoCD インストール用
│   ├── main.tf
│   ├── argocd.tf
│   ├── secrets.tf             # GitHub Token注入
│   └── providers.tf
└── stacks/                    # Atlantisで操作するリソース
```

## 使い方

```bash
# ArgoCD のインストール
cd terraform/bootstrap
terraform init
terraform apply

# Atlantis経由でのリソース管理
# (Atlantis設定後、Pull Requestでterraformコマンドを実行)
```
