# Applications Directory

このディレクトリは、**自作アプリケーション**をデプロイするためのディレクトリです。

## 📁 ディレクトリ構造

```
applications/
├── README.md                    # このファイル
├── _example/                    # サンプルアプリケーション構造
│   ├── base/                    # 共通マニフェスト
│   │   ├── kustomization.yaml
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── ingress.yaml
│   └── overlays/                # 環境別設定
│       ├── production/
│       │   └── kustomization.yaml
│       └── vagrant/
│           └── kustomization.yaml
│
└── your-app/                    # あなたのアプリケーション
    ├── base/
    └── overlays/
```

## 🚀 アプリケーションの追加方法

### 1. アプリケーション構造の作成

```bash
# アプリケーションディレクトリを作成
APP_NAME="my-app"
mkdir -p k8s/applications/${APP_NAME}/{base,overlays/{production,vagrant}}
```

### 2. base マニフェストの作成

`k8s/applications/my-app/base/` に以下のファイルを作成：

**kustomization.yaml**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: my-app

resources:
  - deployment.yaml
  - service.yaml
  - ingress.yaml

commonLabels:
  app.kubernetes.io/name: my-app
  app.kubernetes.io/part-of: applications
```

**deployment.yaml**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app
        image: my-app:latest
        ports:
        - containerPort: 8080
```

**service.yaml**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: my-app
```

**ingress.yaml**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-production
spec:
  ingressClassName: traefik
  tls:
  - hosts:
    - my-app.example.com
    secretName: my-app-tls
  rules:
  - host: my-app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app
            port:
              number: 80
```

### 3. 環境別設定（overlays）の作成

**production/kustomization.yaml**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: my-app

resources:
  - ../../base

patches:
  - patch: |-
      - op: replace
        path: /spec/replicas
        value: 3
    target:
      kind: Deployment
      name: my-app

  - patch: |-
      - op: replace
        path: /spec/rules/0/host
        value: my-app.production.example.com
      - op: replace
        path: /spec/tls/0/hosts/0
        value: my-app.production.example.com
    target:
      kind: Ingress
      name: my-app
```

**vagrant/kustomization.yaml**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: my-app

resources:
  - ../../base

patches:
  - patch: |-
      - op: replace
        path: /spec/replicas
        value: 1
    target:
      kind: Deployment
      name: my-app

  - patch: |-
      - op: replace
        path: /spec/rules/0/host
        value: my-app.vagrant.local
      - op: replace
        path: /spec/tls/0/hosts/0
        value: my-app.vagrant.local
    target:
      kind: Ingress
      name: my-app
```

### 4. ArgoCD Application の作成

`k8s/infrastructure/argocd-apps/base/` に Application マニフェストを作成：

**my-app.yaml**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
  annotations:
    # デプロイ順序を指定（既存インフラの後）
    argocd.argoproj.io/sync-wave: "10"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  source:
    repoURL: https://github.com/kta/raspi-k8s-cluster.git
    targetRevision: main
    path: k8s/applications/my-app/overlays/production  # 環境に応じて変更

  destination:
    server: https://kubernetes.default.svc
    namespace: my-app

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

`k8s/infrastructure/argocd-apps/base/kustomization.yaml` にリソースを追加：
```yaml
resources:
  # ... 既存のリソース
  - my-app.yaml
```

### 5. 環境別パスの設定

`k8s/infrastructure/argocd-apps/overlays/production/kustomization.yaml` にパッチを追加：
```yaml
patches:
  # ... 既存のパッチ

  # My App - production overlay path
  - target:
      kind: Application
      name: my-app
    patch: |-
      - op: replace
        path: /spec/source/path
        value: k8s/applications/my-app/overlays/production
```

`k8s/infrastructure/argocd-apps/overlays/vagrant/kustomization.yaml` にも同様に追加：
```yaml
patches:
  # ... 既存のパッチ

  # My App - vagrant overlay path
  - target:
      kind: Application
      name: my-app
    patch: |-
      - op: replace
        path: /spec/source/path
        value: k8s/applications/my-app/overlays/vagrant
```

### 6. デプロイ

```bash
# 変更をコミット＆プッシュ
git add .
git commit -m "Add my-app application"
git push

# ArgoCDが自動的に同期（automated sync有効の場合）
# または手動同期：
argocd app sync my-app
```

## 🎯 ベストプラクティス

### 命名規則
- アプリケーション名: ケバブケース（例: `my-web-app`, `api-server`）
- Namespace: アプリケーション名と同じ
- リソース名: 短く明確に（例: `deployment`, `service`, `ingress`）

### ディレクトリ構造
- `base/`: 環境に依存しない共通設定
- `overlays/`: 環境固有の設定（IP、ドメイン、レプリカ数など）

### Sync Wave（デプロイ順序）
既存のインフラコンポーネントの後にデプロイされるよう、適切な sync-wave を設定：

| Wave | Component | 用途 |
|------|-----------|------|
| -9 ~ -3 | Infrastructure | インフラコンポーネント |
| 0 ~ 2 | Platform Services | ArgoCD, Atlantis等 |
| **10+** | **Applications** | **自作アプリケーション** |

### リソース管理
- CPU/Memory limits を設定
- Liveness/Readiness probes を実装
- HorizontalPodAutoscaler を検討

### セキュリティ
- Secrets は Sealed Secrets で暗号化
- NetworkPolicy で通信を制限
- Pod Security Standards を適用

## 📚 参照

- [Kustomize公式ドキュメント](https://kustomize.io/)
- [ArgoCD Application仕様](https://argo-cd.readthedocs.io/en/stable/operator-manual/application.yaml)
- [プロジェクトのCLAUDE.md](/CLAUDE.md)

## 🔍 サンプル

`_example/` ディレクトリに完全なサンプルアプリケーション構造があります。参考にしてください。

---

**Note:** インフラコンポーネント（CNI、MetalLB、Cert-Manager等）は `k8s/infrastructure/` に配置されています。このディレクトリは自作アプリケーション専用です。
