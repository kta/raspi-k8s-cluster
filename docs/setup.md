# セットアップガイド

このガイドでは、Proxmox HA Kubernetes Cluster を構築する手順を詳しく説明します。

## 前提条件

以下がすべて完了していることを確認してください：

### 1. Proxmox VE 環境

- [ ] Raspberry Pi 5 (8GB) × 3台に Proxmox VE (Pimox) がインストール済み
- [ ] 物理ノード名が `pi-node-1`, `pi-node-2`, `pi-node-3` に設定済み
- [ ] 3台で Proxmox クラスターが構成済み（定足数が確立されている）
- [ ] 各ノードのIPアドレス:
  - `pi-node-1`: 192.168.100.101
  - `pi-node-2`: 192.168.100.102
  - `pi-node-3`: 192.168.100.103

### 2. Ceph 分散ストレージ

- [ ] Ceph クラスターが構築済み（MON × 3, MGR × 3, OSD × 3）
- [ ] Cephプール `ceph-vm` が作成済み
  ```bash
  # Proxmox UI または CLI で確認
  ssh root@192.168.100.101 "ceph osd pool ls"
  # ceph-vm が表示されること
  
  ssh root@192.168.100.101 "ceph -s"
  # health: HEALTH_OK であること
  ```

### 3. ネットワーク設定

- [ ] 有線 LAN 接続 (Wi-Fi は使用不可)
- [ ] 以下の IP アドレス範囲が未使用:
  - Control Plane: 192.168.100.201-203
  - Worker: 192.168.100.211-213
  - kube-vip VIP: 192.168.100.200
- [ ] ゲートウェイ: 192.168.100.1
- [ ] DNS: 192.168.100.1（または任意のDNSサーバー）

### 4. Proxmox API トークン

API トークンを作成します：

1. Proxmox Web UI にログイン (`https://192.168.100.101:8006`)
2. `Datacenter` → `Permissions` → `API Tokens` を開く
3. `Add` をクリックして新しいトークンを作成:
   - User: `root@pam`
   - Token ID: `terraform`
   - Privilege Separation: **チェックを外す** (フル権限)
4. 生成された Token Secret を保存（後で使用）

### 5. SSH 鍵ペア

- [ ] ローカルマシンに SSH 鍵ペアが存在 (`~/.ssh/id_rsa`, `~/.ssh/id_rsa.pub`)
- [ ] GitHub に公開鍵が登録済み
  ```bash
  # 確認
  curl https://github.com/YOUR_USERNAME.keys
  ```

### 6. ローカル開発環境

- [ ] Homebrew がインストール済み（macOS/Linux）
- [ ] 必要なツールをインストール:
  ```bash
  brew install tfenv tflint kubectl
  tfenv install $(cat .terraform-version)
  tfenv use $(cat .terraform-version)
  tflint --init
  ```

## セットアップ手順

### ステップ1: リポジトリのクローン

```bash
git clone <your-repo-url>
cd raspi-k8s-cluster
```

### ステップ2: 環境変数の設定

`.env` ファイルを作成します：

```bash
cat > .env << 'EOF'
# Proxmox API 接続情報
export PM_API_URL="https://192.168.100.101:8006/"
export PM_API_TOKEN_ID="root@pam!terraform"
export PM_API_TOKEN_SECRET="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Terraform 変数
export TF_VAR_proxmox_api_token_id="${PM_API_TOKEN_ID}"
export TF_VAR_proxmox_api_token_secret="${PM_API_TOKEN_SECRET}"
export TF_VAR_github_username="your-github-username"
EOF

# 環境変数を読み込む
source .env
```

**重要**: `.env` ファイルは `.gitignore` に含まれているため、Git にコミットされません。

### ステップ3: Terraform の初期化

```bash
cd terraform

# プロバイダーとモジュールのダウンロード
terraform init
```

出力例：
```
Initializing the backend...
Initializing provider plugins...
- Finding bpg/proxmox versions matching "~> 0.71.0"...
- Finding hashicorp/helm versions matching "~> 2.17.0"...
...
Terraform has been successfully initialized!
```

### ステップ4: Terraform プランの確認

```bash
# 実行計画を確認（何が作成されるか）
terraform plan
```

以下のリソースが作成される予定であることを確認：
- Debian Cloud Image のダウンロード
- Control Plane VM × 3
- Worker VM × 3
- Kubernetes クラスター初期化
- Flannel CNI
- ArgoCD

### ステップ5: Terraform の適用

```bash
# リソースを作成（約15-20分かかります）
terraform apply

# 確認プロンプトで "yes" を入力
```

**処理フロー**:
1. Debian 13 Trixie ARM64 イメージをダウンロード (約2-3分)
2. 6台のVMを作成 (約3-5分)
3. Cloud-Init でVM初期化 (約3分)
4. Kubernetes クラスター構築 (約5-7分)
5. CNI と ArgoCD インストール (約2-3分)

### ステップ6: kubeconfig の取得

```bash
# kubeconfig をファイルに保存
terraform output -raw kubeconfig > ~/.kube/config-raspi-k8s

# kubectl で使用する
export KUBECONFIG=~/.kube/config-raspi-k8s

# または既存の kubeconfig にマージ
KUBECONFIG=~/.kube/config:~/.kube/config-raspi-k8s kubectl config view --flatten > ~/.kube/config.new
mv ~/.kube/config.new ~/.kube/config
```

### ステップ7: クラスターの確認

```bash
# ノードの状態を確認（全ノードが Ready になるまで待つ）
kubectl get nodes

# 期待される出力:
# NAME          STATUS   ROLES           AGE   VERSION
# pve-vm-cp-1   Ready    control-plane   10m   v1.35.x
# pve-vm-cp-2   Ready    control-plane   9m    v1.35.x
# pve-vm-cp-3   Ready    control-plane   8m    v1.35.x
# pve-vm-wk-1   Ready    <none>          7m    v1.35.x
# pve-vm-wk-2   Ready    <none>          7m    v1.35.x
# pve-vm-wk-3   Ready    <none>          7m    v1.35.x

# すべての Pod が Running になることを確認
kubectl get pods -A

# kube-vip の VIP に疎通確認
curl -k https://192.168.100.200:6443/healthz
# ok
```

### ステップ8: ArgoCD へのアクセス

```bash
# ArgoCD の初期パスワードを取得
terraform output -raw argocd_password

# Port Forward で ArgoCD UI にアクセス
kubectl port-forward svc/argocd-server -n argocd 8080:443

# ブラウザで https://localhost:8080 にアクセス
# ユーザー名: admin
# パスワード: (上記コマンドで取得)
```

## 動作確認

### 1. ノードの分散配置確認

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,NODE:.spec.providerID

# Control Plane が異なる物理ノードに配置されていることを確認
```

### 2. Pod のスケジューリング確認

```bash
# テスト用 Deployment を作成
kubectl create deployment nginx --image=nginx --replicas=3

# Pod が異なるノードに分散されていることを確認
kubectl get pods -o wide
```

### 3. サービスの疎通確認

```bash
# Service を作成
kubectl expose deployment nginx --port=80

# ClusterIP に疎通確認
kubectl run -it --rm debug --image=busybox --restart=Never -- wget -qO- nginx
```

## トラブルシューティング

問題が発生した場合は [troubleshooting.md](./troubleshooting.md) を参照してください。

## 次のステップ

- [ArgoCD App of Apps パターンの構成](./argocd-setup.md)
- [Atlantis のセットアップ](./atlantis-setup.md)
- [メンテナンスガイド](./maintenance.md)
