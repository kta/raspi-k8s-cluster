# クイックスタートガイド

このガイドは、Raspberry Pi Kubernetesクラスタを最短でセットアップするための手順です。

## 🎯 目標

- **所要時間**: 約30分（実機）/ 15分（Vagrant）
- **成果物**: 動作するKubernetesクラスタ + ArgoCD + GitOpsインフラ

## 📋 前提条件

### ハードウェア（実機の場合）
- Raspberry Pi 5 (8GB) × 3台
- microSDカード (64GB以上推奨) × 3台
- ネットワークスイッチ
- 電源アダプタ × 3台

### ソフトウェア（ローカル環境）
```bash
# macOS
brew install ansible terraform kubectl k9s

# Linux (Debian/Ubuntu)
sudo apt-get update
sudo apt-get install -y ansible terraform kubectl

# Vagrantテスト用（オプション）
brew install virtualbox vagrant
```

## 🚀 実機環境セットアップ

### 1. Raspberry PiのIP固定

各Raspberry Piにログインし、IPアドレスを固定します：

```bash
# ノード1 (192.168.1.101)
ssh pi@raspberrypi.local
sudo nmcli connection modify "netplan-eth0" \
  ipv4.addresses 192.168.1.101/24 \
  ipv4.gateway 192.168.1.1 \
  ipv4.dns "8.8.8.8 1.1.1.1" \
  ipv4.method manual
sudo nmcli connection up "netplan-eth0"

# ノード2 (192.168.1.102) と ノード3 (192.168.1.103) も同様に設定
```

### 2. インベントリファイルの確認

`ansible/inventory/inventory.ini` を環境に合わせて編集：

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
ansible_user=pi
vip=192.168.1.100
interface=eth0
k8s_version=1.35
haproxy_port=8443
node_ips=192.168.1.101,192.168.1.102,192.168.1.103
metallb_ip_range=192.168.1.200-192.168.1.220
environment=production
ingress_ip=192.168.1.200
```

### 3. SSH鍵の配布

```bash
make ssh-copy-keys
# または手動で
ssh-copy-id -i ~/.ssh/id_ed25519.pub pi@192.168.1.101
ssh-copy-id -i ~/.ssh/id_ed25519.pub pi@192.168.1.102
ssh-copy-id -i ~/.ssh/id_ed25519.pub pi@192.168.1.103
```

### 4. 全フェーズ一括実行

```bash
make setup-all
```

このコマンドは以下を自動実行します：
1. **Phase 1**: Ansibleでクラスタ構築（kubeadm）
2. **Phase 2**: Terraformでインフラストラクチャブートストラップ（ArgoCD）
3. **Phase 3**: ArgoCDでGitOps管理開始（CNI、MetalLB、Atlantis）

### 5. 動作確認

```bash
# クラスタの状態確認
make status

# 出力例:
# === Nodes ===
# NAME       STATUS   ROLES           AGE   VERSION
# pi-node1   Ready    control-plane   5m    v1.35.0
# pi-node2   Ready    control-plane   4m    v1.35.0
# pi-node3   Ready    control-plane   3m    v1.35.0
```

### 6. ArgoCDアクセス

```bash
# ポートフォワード（最も簡単）
make port-forward-argocd
# ブラウザで http://localhost:8080 にアクセス

# 初期パスワード取得
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

## 🖥️ Vagrant環境セットアップ

実機なしでローカルテスト可能：

```bash
# 1. 全フェーズ一括実行（Vagrant版）
make setup-all-vagrant

# 2. 動作確認
make status

# 3. ArgoCDアクセス
make port-forward-argocd

# 4. 環境破棄
make vagrant-destroy
```

## 🎛️ 個別フェーズ実行

一括実行ではなく、段階的に進めたい場合：

```bash
# Phase 1: クラスタ構築
make ansible-setup
make fetch-kubeconfig

# Phase 2: ArgoCD インストール
make terraform-init
make terraform-plan
make terraform-apply

# Phase 3: GitOpsインフラ
make argocd-bootstrap

# 状態確認
make status
make argocd-status
```

## 🔍 よくある問題

### SSH接続エラー
```bash
# ホスト鍵の問題
ssh-keygen -R 192.168.1.101
ssh-keygen -R 192.168.1.102
ssh-keygen -R 192.168.1.103
```

### Podが起動しない
```bash
# CNI (Flannel) の状態確認
kubectl get pods -n kube-flannel
kubectl logs -n kube-flannel -l app=flannel

# コアコンポーネント確認
kubectl get pods -n kube-system
```

### ArgoCDが見えない
```bash
# Podの状態確認
kubectl get pods -n argocd

# ログ確認
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
```

## 📚 次のステップ

- 📖 [IP管理ガイド](./ip-management.md) - 環境別IP設定の詳細
- 🌐 [サービスアクセスガイド](./service-access.md) - ArgoCD/Atlantisへのアクセス方法
- 🛠️ [トラブルシューティング](./troubleshooting.md) - 問題解決集

## 🆘 ヘルプ

```bash
# 利用可能なコマンド一覧
make help

# 環境設定の確認
make env-info

# 設定の検証
make validate-setup
```
