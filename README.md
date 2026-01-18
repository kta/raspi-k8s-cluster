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
│   ├── roles/
│   │   ├── common/              # swap無効化, cgroup設定(重要), 依存pkg
│   │   ├── container-runtime/   # containerd のインストール & 設定
│   │   └── kubeadm/             # kubeadm init/join の実行
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