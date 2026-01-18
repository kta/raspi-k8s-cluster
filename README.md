# Raspberry Pi Kubernetes Cluster

このプロジェクトは、Raspberry Piクラスター上にKubernetesを構築し、GitOpsによる完全自動化されたインフラストラクチャを実現するためのものです。

## 🏗 アーキテクチャ概要

このプロジェクトは、4つのPhaseで段階的にクラスターを構築します：

- Phase 1: OS設定 & Kubeadm構築 (Ansible)
  - swap無効化、cgroup設定、containerd インストール
  - kubeadm init/join によるクラスター初期構築
- Phase 2: インフラBootstrap (Terraform)
  - ArgoCD のインストール
  - GitHub Token の注入
- Phase 3: GitOps管理 (ArgoCD)
  - CNI (Flannel/Calico)
  - MetalLB (LoadBalancer)
  - Atlantis (Terraform Automation)
- Phase 4: アプリケーションデプロイ
  - Web App等のアプリケーション

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
    │   └── root-app.yaml        # ArgoCD App of Apps
    ├── infra/
    │   ├── cni/                 # ★ Flannel or Calico (CNIは必須)
    │   ├── metallb/             # LoadBalancer
    │   └── atlantis/            # Terraform Automation
    └── apps/
        └── web-app/             # アプリケーション
```

## 🚀 クイックスタート

### 1. 前提条件

* **ハードウェア**: Raspberry Pi 5 (8GB) × 3台
* **OS**: rasbian trixy (raspios_lite_arm64-2020-08-24)
* **ネットワーク**: 固定IPアドレスが割り当てられていること
* **ローカル環境**: Ansible, Terraform, kubectl がインストールされていること

```bash
brew install ansible terraform kubectl

# k8sの状態確認の用、必須ではない
brew install k9s
```

### 2. 設定ファイルの編集

raspberry piのIPを固定していきます
sshで入り、
`ipv4.addresses 192.168.1.101/24` の部分を101-103にそれぞれ修正して、実行してください。

```bash
sudo nmcli connection modify "netplan-eth0" \
  ipv4.addresses 192.168.1.101/24 \
  ipv4.gateway 192.168.1.1 \
  ipv4.dns "8.8.8.8 1.1.1.1" \
  ipv4.method manual

sudo nmcli connection up "netplan-eth0"
```



`ansible/inventory/inventory.ini` を環境に合わせて編集します：

```ini
[all_masters]
pi-node1 ansible_host=192.168.1.101 priority=101 state=MASTER
pi-node2 ansible_host=192.168.1.102 priority=100 state=BACKUP
pi-node3 ansible_host=192.168.1.103 priority=100 state=BACKUP

[primary_master]
pi-node1

[secondary_masters]
pi-node2
pi-node3

[all:vars]
ansible_user=ubuntu
vip=192.168.1.100
interface=eth0
k8s_version=1.35
haproxy_port=8443
node_ips=192.168.1.101,192.168.1.102,192.168.1.103
```

### 3. 全フェーズを一括実行

```bash
# すべてのPhaseを自動で実行
make setup-all
```

または、個別に実行：

```bash

# Phase 0: 鍵交換 (パスワードなしでansibleが動作するように)
make ssh-copy-keys

# Phase 1: Ansibleでクラスター構築
make ansible-setup

# kubeconfigの取得（手元でkubectlを使えるように）
make fetch-kubeconfig

# Phase 2: ArgoCD等をインストール
make terraform-init
make terraform-apply

# Phase 3: GitOps管理の開始
make argocd-bootstrap

# クラスターの状態確認
make status
```

## 📋 利用可能なコマンド一覧

すべてのコマンドは `Makefile` で定義されています。一覧を表示：

```bash
make help
```

### Phase 1: Ansible操作

| コマンド | 説明 |
|---------|------|
| `make ansible-setup` | 本番環境でクラスター構築 |
| `make ansible-setup-vagrant` | Vagrant環境でクラスター構築 |
| `make fetch-kubeconfig` | kubeconfigを取得 |
| `make ansible-verify` | クラスターを検証 |
| `make ansible-reset` | クラスターをリセット |
| `make ansible-upgrade` | クラスターをアップグレード |
| `ansible-dev-debug` | クラスター開発用にセットアップ（Vagrant再構築＋Ansible実行＋検証） |

### Phase 2: Terraform操作

| コマンド | 説明 |
|---------|------|
| `make terraform-init` | Terraformを初期化 |
| `make terraform-plan` | プランを表示 |
| `make terraform-apply` | ArgoCD等をインストール |
| `make terraform-destroy` | リソースを削除 |

### Phase 3: ArgoCD操作

| コマンド | 説明 |
|---------|------|
| `make argocd-bootstrap` | Root Appを適用 |
| `make argocd-sync` | すべてのAppを同期 |
| `make argocd-status` | Appのステータスを表示 |

### Vagrant操作

| コマンド | 説明 |
|---------|------|
| `make vagrant-up` | VMを起動 |
| `make vagrant-halt` | VMを停止 |
| `make vagrant-destroy` | VMを削除 |
| `make vagrant-ssh-primary` | Primary nodeにSSH |

## 💻 ローカル環境でのテスト (Vagrant)

実機を使わずに、PC上の仮想マシンで構築を試すことができます。

### 前提条件

```bash
brew install virtualbox vagrant
```

### 実行手順

```bash
# 1. 仮想マシンの起動
make vagrant-up

# 2. クラスター構築
make ansible-setup-vagrant

# 3. 検証
cd ansible && ansible-playbook -i inventory/inventory_vagrant.ini verify.yml

# 4. 環境の破棄
make vagrant-destroy
```

## 🔄 クラスターのアップグレード

Kubernetes のバージョンアップは、ローリングアップデート（1台ずつ更新）で実施します。

### ⚠️ アップグレードの鉄則

1. **飛び級禁止**: バージョンは必ず「1つずつ」上げる（例: `1.31` → `1.32` はOK、`1.31` → `1.33` はNG）
2. **バックアップ**: 作業前に必ず Etcd のスナップショットを取得
3. **リポジトリ更新**: apt リポジトリのURLがマイナーバージョンごとに異なる

### 実行手順

```bash
# 1. inventory.ini の k8s_version を更新
vi ansible/inventory/inventory.ini
# k8s_version=1.32 に変更

# 2. アップグレード実行
cd ansible
ansible-playbook -i inventory/inventory.ini upgrade.yml -e "target_version=1.32.0-1.1"
```

## 🛠 トラブルシューティング

### ノードが Ready にならない

```bash
# ログを確認
make logs-primary

# または直接確認
vagrant ssh primary -c "sudo journalctl -u kubelet -n 100"
```

### ArgoCD にアクセスできない

```bash
# ArgoCD のパスワードを取得
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# ポートフォワード
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### CNI が動かない

```bash
# Pod の状態確認
kubectl get pods -n kube-system

# CNI のログ確認
kubectl logs -n kube-system -l app=flannel
```

## 🏛 設計思想

**「Ansibleはオーケストレーション（手順管理）に徹し、構築ロジックはシェルスクリプトに集約する」**

これにより、以下のメリットがあります：

* **堅牢性**: Ansible のモジュール仕様変更の影響を受けにくい
* **可読性**: 何をしているか（`kubeadm init` 等）がスクリプトを見れば一目瞭然
* **移植性**: 将来 Ansible をやめても、スクリプト (`ansible/scripts/`) はそのまま再利用可能

## 📚 参考資料

* [Kubernetes公式ドキュメント](https://kubernetes.io/docs/)
* [ArgoCD公式ドキュメント](https://argo-cd.readthedocs.io/)
* [Ansible公式ドキュメント](https://docs.ansible.com/)

## 📄 ライセンス

MIT License
## 🌐 環境別IP管理

このプロジェクトは、**実機（production）** と **Vagrant環境** で異なるIPアドレスレンジを自動的に使い分けます。

### クイックスタート

#### 実機環境（production）
```bash
make ansible-setup ENV=production
make fetch-kubeconfig
make terraform-apply
make argocd-bootstrap
```

#### Vagrant環境
```bash
make ansible-setup-vagrant  # ENV=vagrant が自動設定される
make fetch-kubeconfig-vagrant
make terraform-apply ENV=vagrant
make argocd-bootstrap
```

### IP設定

| 環境 | ノードIP | VIP | MetalLB IPプール | Ingress IP |
|------|---------|-----|----------------|-----------|
| production | 192.168.1.101-103 | 192.168.1.100 | 192.168.1.200-220 | 192.168.1.200 |
| vagrant | 192.168.56.101-103 | 192.168.56.100 | 192.168.56.200-220 | 192.168.56.200 |

### 仕組み

1. **Ansible インベントリ**で環境変数を定義（真実の源）
2. **自動生成スクリプト**がTerraform変数を作成
3. **Kustomize overlays**で環境別マニフェストを管理
4. **ArgoCD**が適切なoverlayをデプロイ

詳細は以下を参照：
- 📖 [環境別IP管理ガイド](docs/environment_ip_management.md) - 完全な仕組みの説明
- ⚡ [クイックスタート](docs/QUICKSTART_IP_MANAGEMENT.md) - すぐに始めたい方向け

### IP設定を変更したい時

```bash
# 1. インベントリファイルを編集
vim ansible/inventory/inventory.ini

# 2. Terraform変数を再生成
make generate-tfvars ENV=production

# 3. ArgoCD Applicationを更新
make patch-argocd-apps ENV=production

# 4. Terraformを再実行
cd terraform/bootstrap && terraform apply
```


## 🌐 サービスアクセス（`/etc/hosts` 不要）

デプロイしたサービス（ArgoCD、Atlantis、Traefik）に `/etc/hosts` を編集せずにアクセスできます。

### 方法1: port-forward（最もシンプル）

```bash
# 全サービスに一度にポートフォワード
make port-forward-all

# または個別に
make port-forward-argocd    # http://localhost:8080
make port-forward-atlantis  # http://localhost:4141
make port-forward-traefik   # http://localhost:9000
```

### 方法2: nip.io（インターネット接続あり）

```bash
# URLを表示
make show-ingress-urls ENV=production

# 出力例:
# http://argocd-192-168-1-200.nip.io
# http://atlantis-192-168-1-200.nip.io
```

### 方法3: dnsmasq（本番に近い環境）

```bash
# ローカルDNSを自動設定（初回のみ）
make setup-local-dns ENV=production

# 以下でアクセス可能になる
# http://argocd.local
# http://atlantis.local
# http://traefik.local
```

詳細は [DNS不要のアクセス方法ガイド](docs/DNS_FREE_ACCESS.md) を参照してください。
