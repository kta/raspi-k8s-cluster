# CLAUDE.md

このファイルは、Claude Code (claude.ai/code) がこのリポジトリのコードを扱う際のガイダンスを提供します。

## プロジェクト概要

Raspberry Pi上に高可用性Kubernetesクラスタを4つのフェーズで構築するプロジェクト：

- **フェーズ1**: OS設定とkubeadmによるクラスタ構築（Ansible）
- **フェーズ2**: ArgoCDインストール（Terraform）
- **フェーズ3**: GitOpsインフラ（CNI、MetalLB、Atlantis）
- **フェーズ4**: アプリケーションデプロイ

## 主要コマンド

すべての操作はMakefileで管理。`make help` で一覧表示。

### クラスタセットアップ
```bash
make setup-all                    # 【本番】全フェーズ実行
make setup-all-vagrant            # 【Vagrant】全フェーズ実行
make ansible-setup                # Phase 1: クラスタ構築（本番）
make ansible-setup-vagrant        # Phase 1: クラスタ構築（Vagrant）
make fetch-kubeconfig             # kubeconfigを取得
make terraform-apply              # Phase 2: ArgoCD インストール
make argocd-bootstrap             # Phase 3: GitOps開始
```

### Vagrant開発
```bash
make vagrant-up                   # VM起動
make vagrant-destroy              # VM破棄
make ansible-dev-debug            # 完全リビルド
```

### クラスタ管理
```bash
make status                       # 状態確認
make ansible-verify               # 検証
make ansible-reset                # リセット
make ansible-upgrade              # アップグレード
```

### サービスアクセス
```bash
make port-forward-all             # 全サービスにポートフォワード
make port-forward-argocd          # ArgoCDアクセス
make show-ingress-urls            # Ingress URL表示
make setup-local-dns              # ローカルDNS設定
```

## アーキテクチャ

### 設計思想
**Ansibleがオーケストレーション、シェルスクリプトがビルドロジック**

- Ansibleモジュールのバージョン互換性問題を回避
- 独立したスクリプトで操作を可視化
- `ansible/scripts/` 内のスクリプトはAnsible無しでも再利用可能

### コアコンポーネント

**ansible/scripts/** - すべてのビルドロジック：
- `common_setup.sh` - OS設定、containerd、kubeadmツール、Keepalived、HAProxy
- `primary_init.sh` - `kubeadm init`、Flannel CNI、参加トークン生成
- `secondary_init.sh` - セカンダリノード用 `kubeadm join`
- `cni_setup.sh` - CNI設定

**ansible/site.yml** - メインPlaybook：
1. 全ノードで `common_setup.sh` 実行
2. プライマリで `primary_init.sh` 実行、joinコマンド取得
3. `add_host` でjoinコマンドを共有
4. セカンダリで `secondary_init.sh` 実行

**インベントリ変数**（`ansible/inventory/*.ini`）：
- `k8s_version` - Kubernetesバージョン（例：1.35）
- `vip` - Keepalived仮想IP
- `interface` - ネットワークインターフェース
- `haproxy_port` - HAProxyポート（デフォルト8443）
- `node_ips` - 全ノードIPのカンマ区切りリスト
- `metallb_ip_range` - MetalLB IPレンジ
- `ingress_ip` - Ingress LoadBalancer IP
- `environment` - 環境識別子（production/vagrant）

### 環境別IP管理

| 環境 | ノードIP | VIP | LoadBalancer IP |
|------|---------|-----|----------------|
| production | 192.168.1.101-103 | 192.168.1.100 | 192.168.1.200-220 |
| vagrant | 192.168.56.101-103 | 192.168.56.100 | 192.168.56.200-220 |

**変数の流れ：**
```
Ansible Inventory
  ↓ (generate_tfvars.sh)
Terraform Variables
  ↓ (terraform apply)
Kubernetes ConfigMap
  ↓ (patch_argocd_apps.sh)
ArgoCD Applications
  ↓ (Kustomize overlays)
環境別マニフェスト
```

### 高可用性セットアップ
- 3ノードコントロールプレーン（taint除去、Pod配置可能）
- Keepalived仮想IPフェイルオーバー
- HAProxyによるAPIサーバー負荷分散
- エンドポイント: VIP:HAProxy_port

## ディレクトリ構成

```
raspi-k8s-cluster/
├── Makefile                     # すべての操作の起点
├── README.md                    # プロジェクト概要
├── CLAUDE.md                    # このファイル
├── docs/                        # ドキュメント
│   ├── README.md                # ドキュメントインデックス
│   ├── guides/                  # ユーザーガイド
│   │   ├── quickstart.md        # クイックスタート
│   │   ├── ip-management.md     # IP管理ガイド
│   │   ├── service-access.md    # サービスアクセス
│   │   └── troubleshooting.md   # トラブルシューティング
│   ├── development/             # 開発者向け
│   │   ├── ci-setup.md
│   │   └── molecule-testing.md
│   └── archived/                # 古いドキュメント
├── ansible/                     # Phase 1: クラスタ構築
│   ├── inventory/
│   │   ├── inventory.ini        # 本番環境
│   │   └── inventory_vagrant.ini # Vagrant環境
│   ├── scripts/                 # ビルドロジック
│   │   ├── common_setup.sh
│   │   ├── primary_init.sh
│   │   ├── secondary_init.sh
│   │   └── cni_setup.sh
│   ├── site.yml                 # メインPlaybook
│   ├── fetch-kubeconfig.yml
│   ├── verify.yml
│   ├── reset.yml
│   └── upgrade.yml
├── terraform/                   # Phase 2: インフラブートストラップ
│   ├── modules/                 # 再利用可能モジュール
│   │   ├── argocd/              # ArgoCDモジュール
│   │   ├── sealed-secrets/      # Sealed Secretsモジュール
│   │   └── atlantis-secrets/    # Atlantis Secretsモジュール
│   ├── environments/            # 環境別設定
│   │   ├── production/          # 本番環境
│   │   │   ├── main.tf
│   │   │   ├── providers.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   ├── terraform.auto.tfvars  # 自動生成（手動編集禁止）
│   │   │   └── terraform.tfvars       # ユーザー設定（gitignore）
│   │   └── vagrant/             # 開発環境
│   ├── README.md                # Terraformドキュメント
│   └── MIGRATION.md             # マイグレーションガイド
├── k8s/                         # Phase 3: GitOps管理リソース
│   ├── bootstrap/
│   │   └── root-app.yaml        # ArgoCD App of Apps
│   ├── infra/
│   │   ├── cni/                 # CNI (Flannel)
│   │   ├── metallb/             # LoadBalancer
│   │   │   ├── base/            # ベースマニフェスト
│   │   │   └── overlays/        # 環境別設定
│   │   │       ├── production/
│   │   │       └── vagrant/
│   │   └── atlantis/            # Terraform Automation
│   └── apps/                    # Phase 4: アプリケーション
└── scripts/                     # 自動化スクリプト
    ├── generate_tfvars.sh       # Terraform変数生成
    ├── patch_argocd_apps.sh     # ArgoCD Application更新
    ├── validate_setup.sh        # 環境検証
    ├── port_forward_services.sh # ポートフォワード
    ├── generate_ingress_urls.sh # URL生成
    └── setup_local_dns.sh       # DNS設定
```

## リンティング

- シェルスクリプト: `shellcheck` 必須
- Ansible Playbook: `ansible-lint` 必須

## 重要なルール

1. **インベントリが真実の源**: すべてのIP設定はAnsibleインベントリで管理
2. **terraform.auto.tfvars は自動生成**: 手動編集禁止、`make generate-tfvars` で生成
3. **環境を明示**: デプロイ時は常に `ENV=production` または `ENV=vagrant` を指定
4. **マニフェストにIP直書き禁止**: Kustomize overlaysを使用
5. **バージョンアップは1つずつ**: Kubernetesは飛び級禁止

## よくあるタスク

### IP設定変更
```bash
vim ansible/inventory/inventory.ini        # IPを編集
make generate-tfvars ENV=production        # Terraform変数再生成
make patch-argocd-apps ENV=production      # ArgoCD更新
cd terraform/bootstrap && terraform apply  # 適用
```

### 環境切り替え
```bash
make env-info ENV=production     # production確認
make env-info ENV=vagrant        # vagrant確認
```

### トラブルシューティング
```bash
make status                      # クラスタ状態
kubectl get pods -A              # Pod確認
kubectl logs -n <namespace> -l <label>  # ログ確認
make ansible-verify              # 検証実行
```

## ドキュメント

詳細は以下を参照：
- 📖 [ドキュメントトップ](docs/README.md)
- 🚀 [クイックスタート](docs/guides/quickstart.md)
- 🌐 [IP管理ガイド](docs/guides/ip-management.md)
- 🔗 [サービスアクセス](docs/guides/service-access.md)
- 🛠️ [トラブルシューティング](docs/guides/troubleshooting.md)
