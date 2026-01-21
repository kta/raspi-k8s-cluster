# Raspberry Pi Kubernetes Cluster

Raspberry Pi上にKubernetesクラスタを構築し、GitOpsで完全自動化されたインフラを実現するプロジェクトです。

## ✨ 特徴

- **高可用性**: 3ノードのコントロールプレーン + Keepalived VIP
- **GitOps管理**: ArgoCD による宣言的インフラ管理
- **包括的監視**: Prometheus + Grafana による完全なクラスタ可視化
- **環境別IP自動管理**: production/vagrant環境の自動切り替え
- **簡単なサービスアクセス**: `/etc/hosts` 編集不要
- **完全自動化**: ワンコマンドでゼロから本番環境構築

## 🏗 アーキテクチャ

4つのフェーズで段階的に構築：

| フェーズ | ツール | 内容 |
|---------|--------|------|
| **Phase 1** | Ansible | OS設定 & kubeadm クラスタ構築 |
| **Phase 2** | Terraform | ArgoCD インストール |
| **Phase 3** | ArgoCD | GitOpsインフラ（CNI、MetalLB、Atlantis）|
| **Phase 4** | ArgoCD | アプリケーションデプロイ |

## 📂 ディレクトリ構成

```text
raspi-k8s-cluster/
├── Makefile                     # ★ すべての操作の起点
├── README.md
├── .gitignore
├── Vagrantfile
│
├── ansible/                     # 【Phase 1: OS設定 & Kubeadm構築】
│   ├── inventory/
│   │   ├── inventory.ini        # 本番環境のインベントリ
│   │   └── inventory_vagrant.ini # Vagrant環境のインベントリ
│   ├── scripts/                 # 構築ロジック（シェルスクリプト）
│   │   ├── common_setup.sh      # 全ノード共通設定
│   │   ├── primary_init.sh      # Primaryノード初期化
│   │   ├── secondary_init.sh    # Secondaryノード参加
│   │   └── cni_setup.sh         # CNIセットアップ
│   ├── site.yml                 # メインPlaybook
│   ├── fetch-kubeconfig.yml     # ★ admin.confを取得
│   ├── reset.yml                # クラスターリセット
│   ├── upgrade.yml              # クラスターアップグレード
│   └── verify.yml               # クラスター検証
│
├── terraform/                   # 【Phase 2 & 4: インフラ & Bootstrap】
│   ├── bootstrap/               # ArgoCD インストール用
│   │   ├── main.tf
│   │   ├── argocd.tf
│   │   ├── secrets.tf           # GitHub Token注入
│   │   └── providers.tf
│   └── stacks/                  # Atlantisで操作するリソース
│
└── k8s/                         # 【Phase 3: GitOps管理リソース】
    ├── bootstrap/
    │   ├── root.yaml            # ⭐ ApplicationSet（全環境対応）
    │   └── values/              # 環境パラメータ
    │       ├── production.yaml  # Production設定
    │       └── vagrant.yaml     # Vagrant設定
    ├── apps/                    # ArgoCD Application定義
    │   ├── base/                # 共通Application定義
    │   │   ├── kustomization.yaml
    │   │   ├── sealed-secrets.yaml
    │   │   ├── cni.yaml
    │   │   ├── metallb.yaml
    │   │   ├── cert-manager.yaml
    │   │   ├── traefik.yaml
    │   │   └── atlantis.yaml
    │   └── overlays/            # 環境別差分
    │       ├── production/
    │       └── vagrant/
    └── infra/                   # Kubernetesマニフェスト
        ├── cni/                 # Pod networking (Flannel)
        ├── metallb/             # LoadBalancer
        ├── cert-manager/        # TLS automation
        ├── traefik/             # Ingress controller
        ├── argocd/              # ArgoCD UI ingress
        └── atlantis/            # Terraform automation
```

## 🚀 クイックスタート

### 前提条件

```bash
# ツールのインストール（macOS）
brew install ansible terraform kubectl k9s

# ハードウェア（実機の場合）
# - Raspberry Pi 5 (8GB) × 3台
# - 固定IPアドレス設定済み
```

### 実機環境（30分）

```bash
# 1. SSH鍵配布
make ssh-copy-keys

# 2. 全フェーズ自動実行
make setup-all

# 3. 動作確認
make status

# 4. ArgoCDアクセス
make port-forward-argocd
# http://localhost:8080
```

### Vagrant環境（15分）

```bash
# 1. 全フェーズ自動実行
make setup-all-vagrant

# 2. 動作確認
make status

# 3. サービスアクセス（直接アクセス可能）
# http://localhost:30080  (ArgoCD)
# http://localhost:3000   (Grafana)
# http://localhost:9090   (Prometheus)

- 監視スタック (NodePort):                                                                            
  - Grafana: http://192.168.56.101:30300                                                              
    - ユーザー: admin                                                                                 
    - パスワード: admin                                                                               
  - Prometheus: http://192.168.56.101:30900                                                           
  - Alertmanager: http://192.168.56.101:30093                                                         
                                                                                                      
- ArgoCD:                                                                                             
  - ArgoCD UI: http://192.168.56.101:30080        

# 4. 環境破棄
make vagrant-destroy
```

📖 **詳細は [クイックスタートガイド](./docs/guides/quickstart.md) を参照**

## 📋 主要コマンド

```bash
# コマンド一覧を表示
make help

# 環境設定を確認
make env-info ENV=production

# クラスタの状態を確認
make status
```

### よく使うコマンド

| カテゴリ | コマンド | 説明 |
|---------|---------|------|
| **セットアップ** | `make setup-all` | 全フェーズ自動実行（実機）|
| | `make setup-all-vagrant` | 全フェーズ自動実行（Vagrant）|
| **アクセス** | `make port-forward-all` | 全サービスにポートフォワード |
| | `make port-forward-argocd` | ArgoCD にアクセス |
| | `make port-forward-grafana` | Grafana にアクセス |
| | `make show-ingress-urls` | Ingress URLを表示 |
| **管理** | `make ansible-verify` | クラスタを検証 |
| | `make ansible-reset` | クラスタをリセット |
| | `make argocd-sync` | ArgoCD 同期 |

📖 **すべてのコマンドは `make help` で確認可能**

## 🌐 環境別IP管理

production/vagrant環境で異なるIPアドレスを自動管理：

| 環境 | ノードIP | VIP | LoadBalancer IP |
|------|---------|-----|----------------|
| production | 192.168.1.101-103 | 192.168.1.100 | 192.168.1.200-220 |
| vagrant | 192.168.56.101-103 | 192.168.56.100 | 192.168.56.200-220 |

```bash
# 環境を指定してセットアップ
make setup-all ENV=production
make setup-all-vagrant  # ENV=vagrant 自動設定

# 環境設定を確認
make env-info ENV=production
```

📖 **詳細は [IP管理ガイド](./docs/guides/ip-management.md) を参照**

## 🔗 サービスアクセス

`/etc/hosts` 編集不要で3つの方法：

```bash
# 方法1: port-forward（最も簡単）
make port-forward-argocd    # http://localhost:8080
make port-forward-grafana   # http://localhost:3000
make port-forward-prometheus # http://localhost:9090

# 方法2: nip.io（DNS不要）
make show-ingress-urls      # http://argocd-192-168-1-200.nip.io

# 方法3: dnsmasq（本番に近い）
make setup-local-dns        # https://argocd.raspi.local
                            # https://grafana.raspi.local
```

📖 **詳細は [サービスアクセスガイド](./docs/guides/service-access.md) を参照**

## 📊 監視スタック

Prometheus + Grafana による包括的なクラスタ監視：

```bash
# Grafana ダッシュボード
make port-forward-grafana
# http://localhost:3000

# Prometheus メトリクス
make port-forward-prometheus
# http://localhost:9090

# 初回ログイン
# ユーザー名: admin
# パスワード: admin
```

**デフォルトダッシュボード:**
- Kubernetes クラスタ全体の概要
- ノード別メトリクス（CPU、メモリ、ディスク）
- Pod/コンテナリソース使用状況
- ArgoCD & Traefik メトリクス

📖 **詳細は [監視ガイド](./docs/guides/monitoring.md) を参照**

## 🛠️ トラブルシューティング

よくある問題と解決策は [トラブルシューティングガイド](./docs/guides/troubleshooting.md) を参照してください。

## 🏛 設計思想

**「Ansibleはオーケストレーション、シェルスクリプトがビルドロジック」**

- **堅牢性**: Ansibleモジュール変更の影響を最小化
- **可読性**: スクリプトを見れば何をしているか一目瞭然
- **移植性**: `ansible/scripts/` は独立して再利用可能

## 📚 ドキュメント

- 📖 [ドキュメントトップ](./docs/README.md) - すべてのドキュメント
- 🚀 [クイックスタート](./docs/guides/quickstart.md) - 最短セットアップ手順
- 🌐 [IP管理ガイド](./docs/guides/ip-management.md) - 環境別IP設定
- 🔗 [サービスアクセス](./docs/guides/service-access.md) - ArgoCD/Atlantis アクセス方法
- 📊 [監視ガイド](./docs/guides/monitoring.md) - Prometheus & Grafana 使い方
- 🛠️ [トラブルシューティング](./docs/guides/troubleshooting.md) - 問題解決集
- ☸️ [k8s構造ガイド](./k8s/README.md) - GitOps構造の詳細説明

## 🔄 最近の更新（2026-01）

### k8s構造の全面リファクタリング v3
- ✅ **インフラのレイヤー化**: 00-04の5層構造で依存関係を明確化
- ✅ **Kustomize→Helm移行**: Pure Helm構成でシンプルに
- ✅ **SealedSecret統合**: 暗号化データをvaluesに直接埋め込み
- ✅ **完全自動化**: ApplicationSetによる環境別自動デプロイ

詳細は [k8s/REFACTORING_2026.md](./k8s/REFACTORING_2026.md) を参照。

## 📄 ライセンス

MIT License
