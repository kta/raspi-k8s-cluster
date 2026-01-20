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
make port-forward-grafana         # Grafanaアクセス
make port-forward-prometheus      # Prometheusアクセス
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
- `cluster_env` - 環境識別子（production/vagrant）

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
  ↓ (ApplicationSet)
ArgoCD Applications
  ↓ (Kustomize overlays)
環境別マニフェスト
```

### k8s構造の特徴

**最新構造（2026年1月リファクタリング v2）**:
- **ApplicationSet**: `bootstrap/root.yaml`が全環境を自動検出
- **base/overlays パターン**: 共通定義と環境差分を分離
- **sync-wave 順序管理**: 番号プレフィックス廃止、アノテーションで依存管理
- **infrastructure/ 統合**: ArgoCD Application CRDとK8sマニフェストを `infrastructure/` に統合
- **applications/ 分離**: 自作アプリケーション専用ディレクトリで、インフラとアプリを明確に分離

**デプロイ順序（sync-wave）**:
| Wave | Component | 目的 | 配置場所 |
|------|-----------|------|----------|
| -9 | sealed-secrets | Secret暗号化 | infrastructure/ |
| -8 | cni | Pod networking | infrastructure/ |
| -7 | metallb | LoadBalancer controller | infrastructure/ |
| -6 | cert-manager, metallb-config | TLS自動化 + IP pool | infrastructure/ |
| -5 | cert-manager-resources | ClusterIssuers | infrastructure/ |
| -4 | traefik | Ingress controller | infrastructure/ |
| -3 | traefik-middleware | Middleware設定 | infrastructure/ |
| 0 | argocd-ingress | ArgoCD UI | infrastructure/ |
| 1 | atlantis | Terraform自動化 | infrastructure/ |
| 2 | atlantis-ingress | Atlantis webhook | infrastructure/ |
| 3 | kube-prometheus-stack | 監視スタック（Prometheus+Grafana） | infrastructure/ |
| 4 | grafana-ingress | Grafana UI | infrastructure/ |
| **10+** | **自作アプリ** | **ユーザーアプリケーション** | **applications/** |

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
│   │   ├── monitoring.md        # 監視ガイド（Prometheus+Grafana）
│   │   └── troubleshooting.md   # トラブルシューティング
│   ├── development/             # 開発者向け
│   │   ├── ci-setup.md
│   │   └── molecule-testing.md
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
│   ├── bootstrap/               # エントリーポイント
│   │   ├── root.yaml            # ⭐ ApplicationSet（Terraform管理・リファレンス用）
│   │   └── values/              # 環境パラメータ
│   │       ├── production.yaml  # Production設定（IP、ドメイン等）
│   │       └── vagrant.yaml     # Vagrant設定（IP、ドメイン等）
│   │
│   ├── infrastructure/          # インフラ全体（ArgoCD Apps + Manifests）
│   │   ├── argocd-apps/         # ArgoCD Application CRD定義
│   │   │   ├── base/            # 共通Application定義
│   │   │   │   ├── kustomization.yaml    # sync-wave順序管理
│   │   │   │   ├── sealed-secrets.yaml   # Wave -9
│   │   │   │   ├── cni.yaml              # Wave -8
│   │   │   │   ├── metallb.yaml          # Wave -7,-6
│   │   │   │   ├── cert-manager.yaml     # Wave -6
│   │   │   │   ├── cert-manager-resources.yaml # Wave -5
│   │   │   │   ├── traefik.yaml          # Wave -4,-3
│   │   │   │   ├── argocd-ingress.yaml   # Wave 0
│   │   │   │   ├── atlantis.yaml         # Wave 1,2
│   │   │   │   └── kube-prometheus-stack.yaml # Wave 3,4
│   │   │   └── overlays/        # 環境別差分（パス書き換え）
│   │   │       ├── production/
│   │   │       │   └── kustomization.yaml
│   │   │       └── vagrant/
│   │   │           └── kustomization.yaml
│   │   │
│   │   ├── cni/                 # Kubernetesマニフェスト（実リソース）
│   │   │   └── base/
│   │   │       ├── kustomization.yaml
│   │   │       └── kube-flannel.yml
│   │   ├── metallb/
│   │   │   ├── base/
│   │   │   │   ├── kustomization.yaml
│   │   │   │   └── ip-pool.yaml
│   │   │   └── overlays/
│   │   │       ├── production/  # IP: 192.168.1.200-220
│   │   │       └── vagrant/     # IP: 192.168.56.200-220
│   │   ├── cert-manager/
│   │   │   ├── base/
│   │   │   │   ├── kustomization.yaml
│   │   │   │   └── cluster-issuer.yaml
│   │   │   └── overlays/
│   │   │       ├── production/  # ACME: production
│   │   │       └── vagrant/     # ACME: staging
│   │   ├── traefik/
│   │   │   └── base/
│   │   │       └── middleware.yaml
│   │   ├── argocd/
│   │   │   ├── base/
│   │   │   │   └── ingress.yaml
│   │   │   └── overlays/
│   │   │       ├── production/
│   │   │       └── vagrant/
│   │   ├── atlantis/
│   │   │   ├── base/
│   │   │   │   └── ingress.yaml
│   │   │   └── overlays/
│   │   │       ├── production/
│   │   │       └── vagrant/
│   │   └── sealed-secrets/      # （Helm chartなのでマニフェスト不要）
│   │
│   └── applications/            # 自作アプリケーション専用
│       ├── README.md            # アプリケーション追加ガイド
│       └── _example/            # サンプルアプリケーション構造
│           ├── base/
│           │   ├── kustomization.yaml
│           │   ├── deployment.yaml
│           │   ├── service.yaml
│           │   └── ingress.yaml
│           └── overlays/
│               ├── production/
│               └── vagrant/
└── scripts/                     # 自動化スクリプト
    ├── generate_tfvars.sh       # Terraform変数生成
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
3. **ApplicationSet は Terraform 管理**: `k8s/bootstrap/root.yaml` は手動適用禁止、Terraformで管理
4. **環境を明示**: デプロイ時は常に `ENV=production` または `ENV=vagrant` を指定
5. **マニフェストにIP直書き禁止**: Kustomize overlaysを使用
6. **バージョンアップは1つずつ**: Kubernetesは飛び級禁止
7. **Git branchで環境を分離可能**: `git_revision` 変数で異なるbranchを環境ごとに指定可能

## Git Branch戦略とベストプラクティス

### 環境ごとのGit Branch設定（推奨）

ApplicationSetの `git_revision` パラメータを使って、環境ごとに異なるGit branchを指定できます：

```bash
# Vagrant環境: develop branchを使用
# terraform/environments/vagrant/terraform.tfvars
git_revision = "develop"

# Production環境: main branchを使用
# terraform/environments/production/terraform.tfvars
git_revision = "main"
```

**ワークフロー例:**
1. 開発: `develop` branchで作業 → Vagrant環境に自動デプロイ
2. テスト: Vagrant環境で動作確認
3. リリース: `develop` を `main` にマージ → Production環境に自動デプロイ

**メリット:**
- 環境ごとに異なるコードバージョンを実行可能
- Production環境への影響なしに開発・テスト可能
- GitOpsの真のメリットを享受

### 環境切り替えの注意点

- **単一クラスタで複数環境を同時に実行することはできません**
- Vagrant環境とProduction環境は異なるクラスタで実行
- 環境変数 `ENV` でTerraformの対象環境を切り替え

## よくあるタスク

### 新しいk8s構造での作業（2026-01リファクタリング v2後）

**ApplicationSetを使った環境別デプロイ:**
```bash
# ApplicationSetはTerraformで管理されています
# Terraform適用時に自動的に作成・更新されます
make terraform-apply ENV=vagrant  # または ENV=production

# 確認
kubectl get appset -n argocd
kubectl get app -n argocd | grep infra-

# 注意: k8s/bootstrap/root.yamlは手動適用禁止（リファレンス用）
```

**インフラコンポーネントの追加:**
```bash
# 1. ArgoCD Application定義を作成
vim k8s/infrastructure/argocd-apps/base/my-infra.yaml  # sync-wave設定
vim k8s/infrastructure/argocd-apps/base/kustomization.yaml  # リソース追加

# 2. Kubernetesマニフェスト作成
mkdir -p k8s/infrastructure/my-infra/{base,overlays/{production,vagrant}}
vim k8s/infrastructure/my-infra/base/deployment.yaml
vim k8s/infrastructure/my-infra/base/kustomization.yaml

# 3. 環境別差分（必要な場合のみ）
vim k8s/infrastructure/my-infra/overlays/production/kustomization.yaml
vim k8s/infrastructure/my-infra/overlays/vagrant/kustomization.yaml

# 4. Application overlayでパッチ
vim k8s/infrastructure/argocd-apps/overlays/production/kustomization.yaml
vim k8s/infrastructure/argocd-apps/overlays/vagrant/kustomization.yaml

# 5. コミット & push → ArgoCD自動同期
git add . && git commit -m "Add my-infra" && git push
```

**自作アプリケーションの追加:**
```bash
# 詳細は k8s/applications/README.md を参照
# サンプル構造: k8s/applications/_example/

# クイックスタート
APP_NAME="my-app"
mkdir -p k8s/applications/${APP_NAME}/{base,overlays/{production,vagrant}}

# マニフェスト作成（deployment, service, ingress等）
vim k8s/applications/${APP_NAME}/base/kustomization.yaml
vim k8s/applications/${APP_NAME}/base/deployment.yaml

# ArgoCD Application定義を追加
vim k8s/infrastructure/argocd-apps/base/${APP_NAME}.yaml

# コミット & デプロイ
git add . && git commit -m "Add ${APP_NAME}" && git push
```

### IP設定変更（新構造対応）
```bash
# 1. Ansibleインベントリを編集
vim ansible/inventory/inventory.ini        # IPを編集

# 2. ApplicationSet環境パラメータを編集
vim k8s/bootstrap/values/production.yaml   # metallb.ipRange等を編集

# 3. Kustomize overlaysを編集（必要に応じて）
vim k8s/infrastructure/metallb/overlays/production/kustomization.yaml

# 4. Terraform変数再生成
make generate-tfvars ENV=production        # Terraform変数再生成

# 5. コミット & push
git add . && git commit -m "Update production IPs" && git push

# 6. ApplicationSet再適用（環境パラメータ反映）
kubectl apply -f k8s/bootstrap/root.yaml

# 7. ArgoCD同期
argocd app sync -l app.kubernetes.io/instance=infra-production
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
