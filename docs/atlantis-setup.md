# Atlantis セットアップガイド

Atlantis を使用して、Pull Request 駆動で Terraform を実行する方法を説明します。

## 概要

Atlantis は、GitHub の Pull Request に対して自動的に `terraform plan` / `apply` を実行するツールです。

- **フェーズ1**: ローカルまたは別サーバーで Docker Compose を使用
- **フェーズ2**: Kubernetes クラスター構築後、セルフホスト Pod として移行

## フェーズ1: Docker Compose で起動

### 前提条件

1. Docker と Docker Compose がインストール済み
2. GitHub Personal Access Token の発行
3. Webhook Secret の生成

### 1. GitHub Personal Access Token の作成

1. GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
2. "Generate new token (classic)" をクリック
3. 以下のスコープを選択:
   - `repo` (フルアクセス)
   - `admin:repo_hook` (webhook 管理)
4. Token を生成して保存

### 2. Webhook Secret の生成

```bash
# ランダムな Secret を生成
openssl rand -hex 32
```

### 3. 環境変数の設定

`.env.atlantis` ファイルを作成：

```bash
cat > .env.atlantis << 'EOF'
# GitHub 設定
GITHUB_USERNAME=your-github-username
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
ATLANTIS_WEBHOOK_SECRET=your-webhook-secret

# Proxmox API（既存の .env から取得）
PM_API_URL=https://192.168.100.101:8006/
PM_API_TOKEN_ID=root@pam!terraform
PM_API_TOKEN_SECRET=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
EOF
```

### 4. Atlantis の起動

```bash
# 環境変数を読み込む
source .env.atlantis

# Docker Compose で起動
docker-compose -f docker-compose.atlantis.yaml up -d

# ログを確認
docker-compose -f docker-compose.atlantis.yaml logs -f
```

### 5. GitHub Webhook の設定

1. GitHub リポジトリ → Settings → Webhooks → Add webhook
2. 以下を設定:
   - **Payload URL**: `http://your-server-ip:4141/events`
   - **Content type**: `application/json`
   - **Secret**: `.env.atlantis` の `ATLANTIS_WEBHOOK_SECRET`
   - **Which events**: "Let me select individual events"
     - ✅ Pull request reviews
     - ✅ Pushes
     - ✅ Issue comments
     - ✅ Pull requests
3. "Add webhook" をクリック

### 6. 動作確認

**Pull Request を作成してテスト**:

1. ブランチを作成して変更を加える:
   ```bash
   git checkout -b test-atlantis
   echo "# Test" >> terraform/test.tf
   git add terraform/test.tf
   git commit -m "Test Atlantis"
   git push origin test-atlantis
   ```

2. GitHub で Pull Request を作成

3. PR のコメント欄に以下を入力:
   ```
   atlantis plan
   ```

4. Atlantis が自動的に `terraform plan` を実行し、結果をコメントで返す

5. 結果を確認後、以下をコメント:
   ```
   atlantis apply
   ```

6. Atlantis が `terraform apply` を実行

## フェーズ2: Kubernetes へ移行

クラスター構築後、Atlantis を Kubernetes Pod として実行します。

### 1. Namespace 作成

```bash
kubectl create namespace atlantis
```

### 2. Secret 作成

```bash
# GitHub トークン
kubectl create secret generic atlantis-github \
  --from-literal=token=${GITHUB_TOKEN} \
  -n atlantis

# Webhook Secret
kubectl create secret generic atlantis-webhook \
  --from-literal=secret=${ATLANTIS_WEBHOOK_SECRET} \
  -n atlantis

# Proxmox API トークン
kubectl create secret generic atlantis-proxmox \
  --from-literal=token_id=${PM_API_TOKEN_ID} \
  --from-literal=token_secret=${PM_API_TOKEN_SECRET} \
  -n atlantis
```

### 3. Deployment マニフェスト

`atlantis-deployment.yaml` を作成:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: atlantis
  namespace: atlantis
spec:
  replicas: 1
  selector:
    matchLabels:
      app: atlantis
  template:
    metadata:
      labels:
        app: atlantis
    spec:
      containers:
      - name: atlantis
        image: ghcr.io/runatlantis/atlantis:latest
        env:
        - name: ATLANTIS_GH_USER
          value: "your-github-username"
        - name: ATLANTIS_GH_TOKEN
          valueFrom:
            secretKeyRef:
              name: atlantis-github
              key: token
        - name: ATLANTIS_GH_WEBHOOK_SECRET
          valueFrom:
            secretKeyRef:
              name: atlantis-webhook
              key: secret
        - name: ATLANTIS_REPO_ALLOWLIST
          value: "github.com/your-github-username/*"
        - name: ATLANTIS_ATLANTIS_URL
          value: "https://your-domain.com"
        - name: PM_API_URL
          value: "https://192.168.100.101:8006/"
        - name: PM_API_TOKEN_ID
          valueFrom:
            secretKeyRef:
              name: atlantis-proxmox
              key: token_id
        - name: PM_API_TOKEN_SECRET
          valueFrom:
            secretKeyRef:
              name: atlantis-proxmox
              key: token_secret
        ports:
        - containerPort: 4141
        volumeMounts:
        - name: atlantis-data
          mountPath: /atlantis-data
      volumes:
      - name: atlantis-data
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: atlantis
  namespace: atlantis
spec:
  type: ClusterIP
  ports:
  - port: 4141
    targetPort: 4141
  selector:
    app: atlantis
```

### 4. Ingress 設定（オプション）

外部からアクセスする場合は Ingress を設定:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: atlantis
  namespace: atlantis
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
  - hosts:
    - atlantis.your-domain.com
    secretName: atlantis-tls
  rules:
  - host: atlantis.your-domain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: atlantis
            port:
              number: 4141
```

### 5. デプロイ

```bash
kubectl apply -f atlantis-deployment.yaml
```

### 6. 動作確認

```bash
# Pod の状態を確認
kubectl get pods -n atlantis

# ログを確認
kubectl logs -n atlantis -l app=atlantis -f

# Port Forward でアクセス（テスト用）
kubectl port-forward -n atlantis svc/atlantis 4141:4141
```

## Atlantis の使い方

### 基本コマンド

Pull Request のコメント欄で以下のコマンドを使用：

```bash
# Plan を実行
atlantis plan

# Apply を実行
atlantis apply

# 特定のプロジェクトのみ Plan
atlantis plan -p raspi-k8s-cluster

# 特定のディレクトリのみ Plan
atlantis plan -d terraform/

# ヘルプを表示
atlantis help
```

### ワークフロー例

1. **機能ブランチを作成**
   ```bash
   git checkout -b feature/add-worker-node
   ```

2. **Terraform コードを変更**
   ```bash
   vim terraform/variables.tf
   # Worker を追加
   ```

3. **変更をコミット & Push**
   ```bash
   git add terraform/variables.tf
   git commit -m "Add 4th worker node"
   git push origin feature/add-worker-node
   ```

4. **Pull Request を作成**
   - GitHub でPRを作成

5. **Atlantis が自動的に Plan を実行**
   - PR 作成時に自動実行される（`autoplan: enabled`）
   - または手動で `atlantis plan` をコメント

6. **Plan 結果を確認**
   - Atlantis がコメントで結果を返す
   - 変更内容を確認

7. **Apply を実行**
   - コメントに `atlantis apply` と入力
   - または PR を Approve してマージ（`apply_requirements: [approved]`）

8. **マージ**
   - Apply 完了後、PR をマージ

## トラブルシューティング

### Atlantis が反応しない

```bash
# Webhook の配信履歴を確認
# GitHub: Settings → Webhooks → Recent Deliveries

# Atlantis のログを確認
docker-compose -f docker-compose.atlantis.yaml logs -f
# または
kubectl logs -n atlantis -l app=atlantis -f
```

### Terraform の実行が失敗する

```bash
# 環境変数が正しく設定されているか確認
docker exec atlantis env | grep PM_API

# Proxmox への接続を確認
docker exec atlantis curl -k ${PM_API_URL}
```

### Apply が実行されない

PR が以下を満たしているか確認:
- [ ] Approved されている
- [ ] Mergeable である（コンフリクトがない）

## セキュリティのベストプラクティス

1. **Webhook Secret を設定**
   - 必ず強力な Secret を使用

2. **Repo Allowlist を制限**
   - 信頼できるリポジトリのみ許可

3. **HTTPS を使用**
   - Ingress で TLS を設定

4. **Secret の管理**
   - Kubernetes Secret または外部 Secret Manager を使用
   - 環境変数に直接書かない

5. **Apply 権限を制限**
   - `apply_requirements` で承認を必須にする

## 参考資料

- [Atlantis 公式ドキュメント](https://www.runatlantis.io/)
- [GitHub Webhook ガイド](https://docs.github.com/en/developers/webhooks-and-events/webhooks)
