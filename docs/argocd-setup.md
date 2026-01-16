# ArgoCD App of Apps セットアップガイド

ArgoCD を使用して、アプリケーションを GitOps で管理する方法を説明します。

## App of Apps パターンとは

**App of Apps** は、ArgoCD の推奨パターンで、1つのルートアプリケーションが複数の子アプリケーションを管理します。

```
app-of-apps (Root)
├── monitoring (Prometheus + Grafana)
├── cert-manager (証明書管理)
└── nginx-demo (サンプルアプリ)
```

## ディレクトリ構造

```
argocd-apps/
├── app-of-apps.yaml          # ルートアプリケーション
├── bootstrap/                 # 子アプリケーション定義
│   ├── monitoring.yaml
│   ├── cert-manager.yaml
│   └── nginx-demo.yaml
└── applications/              # 実際のマニフェスト
    └── nginx-demo.yaml
```

## セットアップ手順

### 1. リポジトリの準備

**重要**: `argocd-apps/` 内の `YOUR_USERNAME` を実際の GitHub ユーザー名に置き換えてください。

```bash
# app-of-apps.yaml を編集
vim argocd-apps/app-of-apps.yaml
# repoURL を変更: https://github.com/YOUR_USERNAME/raspi-k8s-cluster.git

# nginx-demo.yaml を編集
vim argocd-apps/bootstrap/nginx-demo.yaml
# repoURL を変更
```

### 2. 変更をコミット & プッシュ

```bash
git add argocd-apps/
git commit -m "Add ArgoCD App of Apps configuration"
git push origin main
```

### 3. App of Apps をデプロイ

```bash
# kubeconfig を設定
export KUBECONFIG=~/.kube/config-raspi-k8s

# ルートアプリケーションを作成
kubectl apply -f argocd-apps/app-of-apps.yaml

# 数秒後、子アプリケーションが自動的に作成される
kubectl get applications -n argocd

# 期待される出力:
# NAME           SYNC STATUS   HEALTH STATUS
# app-of-apps    Synced        Healthy
# monitoring     Synced        Healthy
# cert-manager   Synced        Healthy
# nginx-demo     Synced        Healthy
```

### 4. ArgoCD UI で確認

```bash
# ArgoCD UI にアクセス
kubectl port-forward svc/argocd-server -n argocd 8080:443

# ブラウザで https://localhost:8080 を開く
# ユーザー名: admin
# パスワード: terraform output -raw argocd_password
```

## デプロイ済みアプリケーション

### 1. Monitoring (Prometheus + Grafana)

**アクセス方法**:

```bash
# Grafana にアクセス
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# ブラウザで http://localhost:3000
# ユーザー名: admin
# パスワード: admin (初回ログイン時に変更を促される)
```

**主な機能**:
- Prometheus: メトリクス収集
- Grafana: ダッシュボード可視化
- Alertmanager: アラート管理

**ダッシュボード例**:
- Kubernetes / Compute Resources / Cluster
- Kubernetes / Compute Resources / Namespace (Pods)
- Node Exporter / Nodes

### 2. Cert-Manager

証明書の自動管理ツール。Let's Encrypt などと連携可能。

**動作確認**:

```bash
# Cert-Manager の Pod を確認
kubectl get pods -n cert-manager

# ClusterIssuer を作成（例: Let's Encrypt）
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

### 3. Nginx Demo

サンプルの Nginx アプリケーション（3レプリカ）。

**アクセス方法**:

```bash
# Service を確認
kubectl get svc -n demo

# Port Forward でアクセス
kubectl port-forward -n demo svc/nginx-demo 8081:80

# ブラウザまたは curl
curl http://localhost:8081
```

## 新しいアプリケーションの追加

### 方法1: Helm Chart をデプロイ

`argocd-apps/bootstrap/` に新しいファイルを作成：

```yaml
# argocd-apps/bootstrap/redis.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: redis
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://charts.bitnami.com/bitnami
    chart: redis
    targetRevision: 20.6.0
    helm:
      values: |
        auth:
          enabled: false
        master:
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
  destination:
    server: https://kubernetes.default.svc
    namespace: redis
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

```bash
# コミット & プッシュ
git add argocd-apps/bootstrap/redis.yaml
git commit -m "Add Redis application"
git push

# ArgoCD が自動的に検出してデプロイ（約1-2分）
kubectl get applications -n argocd
```

### 方法2: Kubernetes マニフェストをデプロイ

1. `argocd-apps/applications/` にマニフェストを配置
2. `argocd-apps/bootstrap/` にアプリケーション定義を作成
3. コミット & プッシュ

## GitOps ワークフロー

### シナリオ: Nginx のレプリカ数を変更

```bash
# 1. ブランチを作成
git checkout -b increase-nginx-replicas

# 2. マニフェストを編集
vim argocd-apps/applications/nginx-demo.yaml
# replicas: 3 → 5

# 3. コミット & プッシュ
git add argocd-apps/applications/nginx-demo.yaml
git commit -m "Increase nginx replicas to 5"
git push origin increase-nginx-replicas

# 4. Pull Request を作成

# 5. レビュー & マージ

# 6. ArgoCD が自動的に同期（約1分）
kubectl get pods -n demo
# nginx-demo-xxx の Pod が5個になる
```

## Sync Policy の設定

### 自動同期 (Automated Sync)

変更を Git にプッシュすると自動的にデプロイ：

```yaml
syncPolicy:
  automated:
    prune: true       # 削除されたリソースも削除
    selfHeal: true    # 手動変更を元に戻す
```

### 手動同期 (Manual Sync)

ArgoCD UI または CLI で手動同期：

```bash
# CLI で同期
argocd app sync nginx-demo

# または UI で "SYNC" ボタンをクリック
```

## トラブルシューティング

### アプリケーションが OutOfSync

**原因**: Git の内容とクラスターの状態が一致していない

**解決方法**:

```bash
# 差分を確認
argocd app diff nginx-demo

# 強制同期
argocd app sync nginx-demo --force
```

### アプリケーションが Degraded

**原因**: Pod が起動しない、リソース不足など

**解決方法**:

```bash
# Pod の状態を確認
kubectl get pods -n <namespace>

# ログを確認
kubectl logs -n <namespace> <pod-name>

# リソースを確認
kubectl describe pod -n <namespace> <pod-name>
```

### Git リポジトリに接続できない

```bash
# ArgoCD の Repo を確認
argocd repo list

# Repo を追加（必要に応じて）
argocd repo add https://github.com/YOUR_USERNAME/raspi-k8s-cluster.git \
  --username YOUR_USERNAME \
  --password YOUR_GITHUB_TOKEN
```

## ベストプラクティス

### 1. 環境ごとにディレクトリを分ける

```
argocd-apps/
├── base/                   # 共通設定
├── overlays/
│   ├── dev/               # 開発環境
│   ├── staging/           # ステージング環境
│   └── production/        # 本番環境
```

### 2. リソース制限を必ず設定

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi
```

### 3. Namespace を分ける

機能ごとに Namespace を作成：
- `monitoring`: 監視系
- `logging`: ログ収集
- `ingress`: Ingress Controller
- `apps`: ビジネスアプリ

### 4. Secrets の管理

機密情報は Sealed Secrets または External Secrets Operator を使用：

```bash
# Sealed Secrets のインストール
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.4/controller.yaml

# Secret を暗号化
kubeseal --format=yaml < secret.yaml > sealed-secret.yaml

# Git にコミット
git add sealed-secret.yaml
```

## 参考資料

- [ArgoCD 公式ドキュメント](https://argo-cd.readthedocs.io/)
- [App of Apps パターン](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
