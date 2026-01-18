# Phase 2 & 3: Terraform と ArgoCD による GitOps 環境構築

このドキュメントでは、Phase 1 で構築した Kubernetes クラスタに対して、Terraform で ArgoCD をインストールし（Phase 2）、ArgoCD を用いた GitOps でインフラコンポーネントを管理する（Phase 3）手順を解説します。

## 目次

1. [アーキテクチャ概要](#1-アーキテクチャ概要)
2. [前提条件](#2-前提条件)
3. [ディレクトリ構造](#3-ディレクトリ構造)
4. [Phase 2: Terraform による ArgoCD インストール](#4-phase-2-terraform-による-argocd-インストール)
5. [Phase 3: ArgoCD による GitOps 管理](#5-phase-3-argocd-による-gitops-管理)
6. [セキュアな Secret 管理（Sealed Secrets）](#6-セキュアな-secret-管理sealed-secrets)
7. [Ingress と TLS 証明書管理](#7-ingress-と-tls-証明書管理)
8. [デプロイ手順](#8-デプロイ手順)
9. [検証](#9-検証)
10. [トラブルシューティング](#10-トラブルシューティング)

---

## 1. アーキテクチャ概要

### 全体の流れ

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         GitOps アーキテクチャ（セキュア版）                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────┐    ┌──────────────┐    ┌────────────────────────────────┐  │
│  │   GitHub    │    │   ArgoCD     │    │      Kubernetes Cluster        │  │
│  │ Repository  │───▶│   Server     │───▶│                                │  │
│  │             │sync│              │    │  ┌────────────────────────┐    │  │
│  │ SealedSecret│    └──────────────┘    │  │    Sealed Secrets      │    │  │
│  │  (暗号化)   │           │            │  │  Controller (復号化)    │    │  │
│  └─────────────┘           │ monitors   │  └────────────────────────┘    │  │
│        │                   ▼            │                                │  │
│        │            ┌──────────────┐    │  ┌────────────────────────┐    │  │
│        │            │ Applications │    │  │   Traefik Ingress      │    │  │
│        │            ├──────────────┤    │  │  + cert-manager (TLS)  │    │  │
│        │            │ - CNI        │    │  └────────────────────────┘    │  │
│        │            │ - MetalLB    │    │            │                   │  │
│        │            │ - Ingress    │    │            ▼                   │  │
│        │            │ - Atlantis   │    │  https://argocd.local          │  │
│        │            │ - Secrets    │    │  https://atlantis.local        │  │
│        │            └──────────────┘    │                                │  │
│        │                                └────────────────────────────────┘  │
│        │                                                                    │
│        └────────────── Atlantis (PR経由でTerraform実行) ◀───────────────────┤
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Phase 2 と Phase 3 の役割

| Phase | 目的 | ツール | 管理対象 |
|-------|------|--------|----------|
| Phase 2 | GitOps基盤構築 | Terraform | ArgoCD, Sealed Secrets Controller |
| Phase 3 | インフラ GitOps 化 | ArgoCD | CNI, MetalLB, Traefik, cert-manager, Atlantis |

### App of Apps パターン

Phase 3 では「App of Apps」パターンを採用します。これは ArgoCD の推奨アーキテクチャで、ルートアプリケーションが他のアプリケーションを管理します。

```
infra-root (Application)
    │
    ├── cni-flannel (Application)           [sync-wave: -10]
    │       └── Flannel CNI
    │
    ├── metallb (Application)               [sync-wave: -5]
    │       └── MetalLB + IPAddressPool
    │
    ├── sealed-secrets (Application)        [sync-wave: -4]
    │       └── Sealed Secrets Controller
    │
    ├── cert-manager (Application)          [sync-wave: -3]
    │       └── cert-manager + ClusterIssuer
    │
    ├── traefik (Application)               [sync-wave: -2]
    │       └── Traefik Ingress Controller
    │
    └── atlantis (Application)              [sync-wave: 0]
            └── Atlantis + Ingress
```

### セキュリティ設計のポイント

| 課題 | 解決策 |
|------|--------|
| Secret を Git に保存できない | Sealed Secrets で暗号化して Git 管理 |
| NodePort でのアクセスが不便 | Traefik Ingress で統一的なアクセス |
| TLS 証明書の管理が煩雑 | cert-manager で自動発行・更新 |
| Terraform に機密情報を書きたくない | 環境変数 or Sealed Secrets を利用 |

---

## 2. 前提条件

### 必須要件

- Phase 1 が完了し、Kubernetes クラスタが稼働していること
- `kubectl` がクラスタに接続できること（`~/.kube/config` 設定済み）
- Terraform >= 1.5.0 がインストールされていること
- Helm >= 3.0 がインストールされていること（検証用）
- GitHub アカウントと Personal Access Token（PAT）

### GitHub Personal Access Token の作成

Atlantis と ArgoCD がプライベートリポジトリにアクセスするために必要です。

1. GitHub Settings → Developer settings → Personal access tokens → Fine-grained tokens
2. 「Generate new token」をクリック
3. 以下の権限を付与:
   - **Repository access**: このリポジトリのみ（または All repositories）
   - **Permissions**:
     - Contents: Read and write
     - Pull requests: Read and write
     - Webhooks: Read and write（Atlantis 用）

### 環境別 IP アドレス設定

| 環境 | ノード IP 範囲 | VIP | MetalLB IP プール |
|------|---------------|-----|-------------------|
| 実機（Raspberry Pi） | 192.168.1.101-103 | 192.168.1.100 | 192.168.1.200-192.168.1.220 |
| Vagrant | 192.168.56.101-103 | 192.168.56.100 | 192.168.56.200-192.168.56.220 |

---

## 3. ディレクトリ構造

以下の構造でファイルを作成します。

```
raspi-k8s-cluster/
├── terraform/
│   └── bootstrap/                    # Phase 2: 基盤インストール
│       ├── providers.tf              # Terraform プロバイダー設定
│       ├── variables.tf              # 変数定義
│       ├── argocd.tf                 # ArgoCD Helm リリース
│       ├── sealed-secrets.tf         # Sealed Secrets Controller
│       ├── outputs.tf                # 出力値
│       └── terraform.tfvars          # 環境固有の値（.gitignore に追加）
│
├── k8s/
│   ├── bootstrap/                    # Phase 3: Root Application
│   │   └── root-app.yaml
│   │
│   ├── infra/                        # Phase 3: インフラコンポーネント
│   │   ├── cni/
│   │   │   └── flannel.yaml
│   │   ├── metallb/
│   │   │   ├── metallb.yaml
│   │   │   └── resources/
│   │   │       └── ip-pool.yaml
│   │   ├── sealed-secrets/
│   │   │   └── sealed-secrets.yaml
│   │   ├── cert-manager/
│   │   │   ├── cert-manager.yaml
│   │   │   └── resources/
│   │   │       └── cluster-issuer.yaml
│   │   ├── traefik/
│   │   │   ├── traefik.yaml
│   │   │   └── resources/
│   │   │       └── middleware.yaml
│   │   └── atlantis/
│   │       ├── atlantis.yaml
│   │       └── resources/
│   │           ├── ingress.yaml
│   │           └── github-secret.yaml  # SealedSecret
│   │
│   └── secrets/                      # Sealed Secrets（暗号化済み）
│       ├── argocd/
│       │   └── repo-creds.yaml
│       └── atlantis/
│           └── github-token.yaml
│
└── docs/
    └── argocd/
        ├── values.yaml               # ArgoCD Helm values
        └── ingress-values.yaml       # Ingress 有効化用の追加 values
```

---

## 4. Phase 2: Terraform による ArgoCD インストール

### 4.1 providers.tf

Kubernetes と Helm プロバイダーの設定です。

```hcl
# terraform/bootstrap/providers.tf

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}
```

### 4.2 variables.tf

変数定義です。機密情報は `terraform.tfvars` で設定します。

```hcl
# terraform/bootstrap/variables.tf

variable "kubeconfig_path" {
  type        = string
  default     = "~/.kube/config"
  description = "kubeconfig ファイルのパス"
}

variable "argocd_namespace" {
  type        = string
  default     = "argocd"
  description = "ArgoCD をインストールする Namespace"
}

variable "argocd_chart_version" {
  type        = string
  default     = "7.7.16"
  description = "ArgoCD Helm Chart のバージョン"
}

variable "github_token" {
  type        = string
  sensitive   = true
  description = "GitHub Personal Access Token"
}

variable "github_username" {
  type        = string
  description = "GitHub ユーザー名"
}

variable "github_repo_url" {
  type        = string
  description = "GitOps リポジトリの URL（例: https://github.com/user/repo.git）"
}
```

### 4.3 argocd.tf

ArgoCD の Helm リリースを定義します。

```hcl
# terraform/bootstrap/argocd.tf

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.argocd_namespace

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  # Raspberry Pi 向けに最適化された values.yaml を使用
  values = [
    file("${path.module}/../../docs/argocd/values.yaml")
  ]

  # インストール完了まで待機
  wait    = true
  timeout = 900

  depends_on = [kubernetes_namespace.argocd]
}
```

### 4.4 secrets.tf

GitHub 認証用の Secret を作成します。

```hcl
# terraform/bootstrap/secrets.tf

# ArgoCD がプライベートリポジトリにアクセスするための認証情報
resource "kubernetes_secret" "argocd_repo_creds" {
  metadata {
    name      = "repo-creds"
    namespace = kubernetes_namespace.argocd.metadata[0].name

    labels = {
      "argocd.argoproj.io/secret-type" = "repo-creds"
    }
  }

  data = {
    type     = "git"
    url      = "https://github.com"
    username = var.github_username
    password = var.github_token
  }

  type = "Opaque"

  depends_on = [helm_release.argocd]
}

# Atlantis 用の GitHub Secret（Atlantis デプロイ時に使用）
resource "kubernetes_namespace" "atlantis" {
  metadata {
    name = "atlantis"

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_secret" "atlantis_github" {
  metadata {
    name      = "atlantis-github-secret"
    namespace = kubernetes_namespace.atlantis.metadata[0].name
  }

  data = {
    token = var.github_token
  }

  type = "Opaque"
}
```

### 4.5 outputs.tf

デプロイ後の確認に便利な出力値を定義します。

```hcl
# terraform/bootstrap/outputs.tf

output "argocd_namespace" {
  value       = kubernetes_namespace.argocd.metadata[0].name
  description = "ArgoCD がインストールされた Namespace"
}

output "argocd_server_service" {
  value       = "argocd-server"
  description = "ArgoCD Server の Service 名"
}

output "argocd_initial_admin_password_command" {
  value       = "kubectl -n ${var.argocd_namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
  description = "ArgoCD 初期管理者パスワード取得コマンド"
}

output "argocd_port_forward_command" {
  value       = "kubectl port-forward svc/argocd-server -n ${var.argocd_namespace} 8080:443"
  description = "ArgoCD UI へのポートフォワードコマンド"
}

output "argocd_nodeport_url" {
  value       = "https://<NODE_IP>:30443"
  description = "NodePort 経由での ArgoCD UI アクセス URL"
}
```

### 4.6 terraform.tfvars（テンプレート）

環境固有の値を設定します。**このファイルは .gitignore に追加してください。**

```hcl
# terraform/bootstrap/terraform.tfvars
# このファイルは Git にコミットしないでください

github_username = "your-github-username"
github_token    = "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
github_repo_url = "https://github.com/your-username/raspi-k8s-cluster.git"

# オプション: デフォルト値を上書きする場合
# kubeconfig_path      = "~/.kube/config"
# argocd_namespace     = "argocd"
# argocd_chart_version = "7.7.16"
```

---

## 5. Phase 3: ArgoCD による GitOps 管理

### 5.1 Root Application（App of Apps）

すべてのインフラコンポーネントを管理するルートアプリケーションです。

```yaml
# k8s/bootstrap/root-app.yaml

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infra-root
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  source:
    # ここを自分のリポジトリ URL に変更
    repoURL: https://github.com/YOUR_USERNAME/raspi-k8s-cluster.git
    targetRevision: main
    path: k8s/infra
    directory:
      recurse: true

  destination:
    server: https://kubernetes.default.svc
    namespace: argocd

  syncPolicy:
    automated:
      prune: true      # Git から削除されたリソースをクラスタからも削除
      selfHeal: true   # クラスタ上の手動変更を Git の状態に戻す
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

### 5.2 CNI: Flannel

ネットワークプラグインとして Flannel をデプロイします。

```yaml
# k8s/infra/cni/flannel.yaml

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cni-flannel
  namespace: argocd
  annotations:
    # 最初にデプロイ（他のコンポーネントより先に）
    argocd.argoproj.io/sync-wave: "-10"
spec:
  project: default

  source:
    repoURL: https://flannel-io.github.io/flannel
    chart: flannel
    targetRevision: v0.26.4
    helm:
      releaseName: flannel
      valuesObject:
        podCidr: "10.244.0.0/16"
        flannel:
          backend: "vxlan"
        # ARM64 対応イメージを使用
        image:
          repository: flannel/flannel
          tag: v0.26.4

  destination:
    server: https://kubernetes.default.svc
    namespace: kube-flannel

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

### 5.3 MetalLB: ロードバランサー

ベアメタル環境でロードバランサーを提供します。

#### MetalLB アプリケーション

```yaml
# k8s/infra/metallb/metallb.yaml

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: metallb
  namespace: argocd
  annotations:
    # CNI の後にデプロイ
    argocd.argoproj.io/sync-wave: "-5"
spec:
  project: default

  source:
    repoURL: https://metallb.github.io/metallb
    chart: metallb
    targetRevision: 0.14.9
    helm:
      releaseName: metallb

  destination:
    server: https://kubernetes.default.svc
    namespace: metallb-system

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

#### MetalLB IP プール設定

MetalLB がインストールされた後、IP アドレスプールを設定します。

```yaml
# k8s/infra/metallb/config.yaml

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: metallb-config
  namespace: argocd
  annotations:
    # MetalLB 本体の後にデプロイ
    argocd.argoproj.io/sync-wave: "-4"
spec:
  project: default

  source:
    repoURL: https://github.com/YOUR_USERNAME/raspi-k8s-cluster.git
    targetRevision: main
    path: k8s/infra/metallb/resources

  destination:
    server: https://kubernetes.default.svc
    namespace: metallb-system

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

#### MetalLB リソース定義

```yaml
# k8s/infra/metallb/resources/ip-pool.yaml

apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
    # 実機環境の場合
    - 192.168.1.200-192.168.1.220
    # Vagrant 環境の場合は以下に変更
    # - 192.168.56.200-192.168.56.220

---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-l2-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
    - default-pool
```

### 5.4 Atlantis: Terraform PR 自動化

Pull Request 経由で Terraform を実行する Atlantis をデプロイします。

```yaml
# k8s/infra/atlantis/atlantis.yaml

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: atlantis
  namespace: argocd
  annotations:
    # 最後にデプロイ
    argocd.argoproj.io/sync-wave: "0"
spec:
  project: default

  source:
    repoURL: https://runatlantis.github.io/helm-charts
    chart: atlantis
    targetRevision: 5.10.0
    helm:
      releaseName: atlantis
      valuesObject:
        # GitHub 連携設定
        orgAllowlist: "github.com/YOUR_USERNAME/*"

        github:
          user: YOUR_USERNAME
          # Phase 2 で作成した Secret を参照
          secret: atlantis-github-secret
          secretKey: token

        # Webhook Secret（GitHub Webhook 設定時に使用）
        # webhookSecret: "your-webhook-secret"

        # サービス設定
        service:
          type: NodePort
          nodePort: 30141

        # リソース制限（Raspberry Pi 向け）
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi

        # リポジトリ設定
        repoConfig: |
          ---
          repos:
            - id: github.com/YOUR_USERNAME/raspi-k8s-cluster
              branch: /.*/
              allowed_overrides: [workflow, apply_requirements]
              allow_custom_workflows: true

        # Atlantis サーバー設定
        atlantisUrl: http://atlantis.local:30141

  destination:
    server: https://kubernetes.default.svc
    namespace: atlantis

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

---

## 6. デプロイ手順

### 6.1 Phase 2: ArgoCD インストール

```bash
# 1. kubeconfig が設定されていることを確認
kubectl get nodes

# 2. Terraform 初期化
cd terraform/bootstrap
terraform init

# 3. terraform.tfvars を作成（テンプレートを参考に）
cp terraform.tfvars.example terraform.tfvars
# エディタで編集して GitHub 情報を入力

# 4. 実行計画を確認
terraform plan

# 5. 適用
terraform apply

# 6. ArgoCD の起動を確認
kubectl get pods -n argocd -w
```

### 6.2 ArgoCD UI へのアクセス

```bash
# 初期管理者パスワードを取得
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo

# NodePort でアクセス（推奨）
# ブラウザで https://<NODE_IP>:30443 にアクセス
# ユーザー名: admin
# パスワード: 上記で取得した値

# または ポートフォワード
kubectl port-forward svc/argocd-server -n argocd 8080:443
# ブラウザで https://localhost:8080 にアクセス
```

### 6.3 Phase 3: GitOps 開始

```bash
# 1. k8s/ ディレクトリのファイルを作成（上記のマニフェストを参照）

# 2. YOUR_USERNAME を自分のユーザー名に置換
find k8s -name "*.yaml" -exec sed -i '' 's/kta/your-actual-username/g' {} \;

# 3. Git にコミット・プッシュ
git add k8s/
git commit -m "Add GitOps manifests for Phase 3"
git push origin main

# 4. Root Application を適用
make argocd-bootstrap
# または
kubectl apply -f k8s/bootstrap/root-app.yaml

# 5. 同期状況を確認
kubectl get applications -n argocd
```

---

## 7. 検証

### 7.1 ArgoCD アプリケーションの状態確認

```bash
# すべてのアプリケーションを表示
kubectl get applications -n argockubectl get applications -n argocdd

# 期待される出力:
# NAME            SYNC STATUS   HEALTH STATUS
# infra-root      Synced        Healthy
# cni-flannel     Synced        Healthy
# metallb         Synced        Healthy
# metallb-config  Synced        Healthy
# atlantis        Synced        Healthy
```

### 7.2 各コンポーネントの確認

```bash
# Flannel
kubectl get pods -n kube-flannel
kubectl get daemonset -n kube-flannel

# MetalLB
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system

# Atlantis
kubectl get pods -n atlantis
kubectl get svc -n atlantis
```

### 7.3 MetalLB の動作確認

テスト用の LoadBalancer Service を作成して確認します。

```bash
# テスト用 nginx をデプロイ
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=LoadBalancer

# External IP が割り当てられることを確認
kubectl get svc nginx -w

# クリーンアップ
kubectl delete deployment nginx
kubectl delete svc nginx
```

---

## 8. トラブルシューティング

### ArgoCD がリポジトリに接続できない

```bash
# Secret が正しく作成されているか確認
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=repo-creds

# ArgoCD の Repo Server ログを確認
kubectl logs -n argocd -l app.kubernetes.io/component=repo-server

# ArgoCD CLI でリポジトリ接続をテスト
argocd repo list
```

### Flannel Pod が起動しない

```bash
# Pod の状態を確認
kubectl describe pod -n kube-flannel -l app=flannel

# ノードのネットワーク設定を確認
kubectl get nodes -o wide

# CNI 設定ファイルを確認（各ノードで実行）
ls -la /etc/cni/net.d/
```

### MetalLB が IP を割り当てない

```bash
# Speaker Pod のログを確認
kubectl logs -n metallb-system -l component=speaker

# IPAddressPool が正しく作成されているか確認
kubectl describe ipaddresspool -n metallb-system

# L2Advertisement の状態を確認
kubectl describe l2advertisement -n metallb-system
```

### Atlantis Webhook が動作しない

```bash
# Atlantis Pod のログを確認
kubectl logs -n atlantis -l app.kubernetes.io/name=atlantis

# GitHub Webhook の設定を確認
# GitHub リポジトリ → Settings → Webhooks で以下を確認:
# - Payload URL: http://<ATLANTIS_URL>/events
# - Content type: application/json
# - Events: Pull requests, Issue comments, Pushes
```

### Application が Sync されない

```bash
# Application の詳細を確認
kubectl describe application <app-name> -n argocd

# 手動で Sync を実行
kubectl patch application <app-name> -n argocd \
  --type merge -p '{"operation": {"sync": {}}}'

# ArgoCD CLI を使用
argocd app sync <app-name>
```

### Terraform が失敗する

```bash
# 状態をリフレッシュ
terraform refresh

# 特定のリソースのみ再作成
terraform taint <resource_address>
terraform apply

# 完全にやり直す場合（注意: すべて削除されます）
terraform destroy
terraform apply
```

---

## 補足: Makefile コマンド一覧

Phase 2 & 3 関連のコマンドは以下の通りです。

```bash
# Phase 2
make terraform-init      # Terraform 初期化
make terraform-plan      # 実行計画を表示
make terraform-apply     # ArgoCD をインストール
make terraform-destroy   # ArgoCD を削除

# Phase 3
make argocd-bootstrap    # Root Application を適用
make argocd-sync         # すべてのアプリケーションを同期
make argocd-status       # アプリケーション一覧を表示

# 全フェーズ一括実行
make setup-all           # Phase 1〜3 を順番に実行
```

---

## 次のステップ

Phase 2 & 3 が完了したら、以下を検討してください。

1. **Ingress Controller の追加**: NGINX Ingress や Traefik を ArgoCD で管理
2. **証明書管理**: cert-manager を追加して TLS 証明書を自動発行
3. **監視**: Prometheus + Grafana を GitOps で管理
4. **アプリケーションデプロイ（Phase 4）**: 実際のアプリケーションを ArgoCD で管理

---

## 6. セキュアな Secret 管理（Sealed Secrets）

### 6.1 概要

Sealed Secrets は、暗号化された Secret を Git リポジトリに安全に保存できるようにする仕組みです。

**問題点**: 従来の Kubernetes Secret は Base64 エンコードのみで、平文同然です。Git にコミットすると機密情報が漏洩するリスクがあります。

**解決策**: Sealed Secrets Controller が公開鍵暗号を使用して Secret を暗号化します。
- **SealedSecret**: 暗号化された Secret（Git に保存可能）
- **Secret**: クラスタ内で Controller が自動的に復号化

### 6.2 Sealed Secrets Controller のインストール

Phase 2 の Terraform に追加します。

```hcl
# terraform/bootstrap/sealed-secrets.tf

resource "helm_release" "sealed_secrets" {
  name       = "sealed-secrets"
  repository = "https://bitnami-labs.github.io/sealed-secrets"
  chart      = "sealed-secrets"
  version    = "2.16.3"
  namespace  = "kube-system"

  values = [
    yamlencode({
      # Raspberry Pi 向けリソース制限
      resources = {
        requests = {
          cpu    = "50m"
          memory = "64Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "128Mi"
        }
      }
    })
  ]

  wait    = true
  timeout = 300
}

output "sealed_secrets_controller_name" {
  value       = helm_release.sealed_secrets.name
  description = "Sealed Secrets Controller リリース名"
}
```

### 6.3 kubeseal CLI のインストール

ローカルマシンに `kubeseal` コマンドをインストールします。

```bash
# macOS
brew install kubeseal

# Linux
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.4/kubeseal-0.27.4-linux-arm64.tar.gz
tar -xzf kubeseal-0.27.4-linux-arm64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal

# バージョン確認
kubeseal --version
```

### 6.4 Secret の暗号化手順

#### 例1: GitHub Token を暗号化

```bash
# 1. 通常の Secret を作成（まだ適用しない）
kubectl create secret generic atlantis-github-token \
  --from-literal=token=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
  --namespace atlantis \
  --dry-run=client -o yaml > atlantis-github-token-secret.yaml

# 2. kubeseal で暗号化
kubeseal --format yaml \
  --controller-name sealed-secrets \
  --controller-namespace kube-system \
  < atlantis-github-token-secret.yaml \
  > k8s/secrets/atlantis/github-token.yaml

# 3. 元の平文 Secret ファイルを削除（重要！）
rm atlantis-github-token-secret.yaml

# 4. 暗号化された SealedSecret を Git にコミット
git add k8s/secrets/atlantis/github-token.yaml
git commit -m "Add encrypted Atlantis GitHub token"
git push origin main
```

#### 例2: ArgoCD リポジトリ認証情報を暗号化

```bash
# 1. Secret 作成
kubectl create secret generic repo-creds \
  --from-literal=type=git \
  --from-literal=url=https://github.com \
  --from-literal=username=your-username \
  --from-literal=password=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
  --namespace argocd \
  --dry-run=client -o yaml > repo-creds-secret.yaml

# 2. ArgoCD 用のラベルを追加
cat >> repo-creds-secret.yaml << 'EOF'
  labels:
    argocd.argoproj.io/secret-type: repo-creds
EOF

# 3. 暗号化
kubeseal --format yaml \
  --controller-name sealed-secrets \
  --controller-namespace kube-system \
  < repo-creds-secret.yaml \
  > k8s/secrets/argocd/repo-creds.yaml

# 4. クリーンアップしてコミット
rm repo-creds-secret.yaml
git add k8s/secrets/argocd/repo-creds.yaml
git commit -m "Add encrypted ArgoCD repository credentials"
git push origin main
```

### 6.5 SealedSecret の適用

ArgoCD アプリケーションとして管理します。

```yaml
# k8s/infra/sealed-secrets/sealed-secrets.yaml

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sealed-secrets-controller
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-4"
spec:
  project: default

  source:
    repoURL: https://bitnami-labs.github.io/sealed-secrets
    chart: sealed-secrets
    targetRevision: 2.16.3
    helm:
      releaseName: sealed-secrets
      valuesObject:
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi

  destination:
    server: https://kubernetes.default.svc
    namespace: kube-system

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

```yaml
# k8s/infra/sealed-secrets/secrets-app.yaml

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sealed-secrets
  namespace: argocd
  annotations:
    # Controller の後にデプロイ
    argocd.argoproj.io/sync-wave: "-3"
spec:
  project: default

  source:
    repoURL: https://github.com/YOUR_USERNAME/raspi-k8s-cluster.git
    targetRevision: main
    path: k8s/secrets
    directory:
      recurse: true

  destination:
    server: https://kubernetes.default.svc

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### 6.6 動作確認

```bash
# 1. Sealed Secrets Controller が起動していることを確認
kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets

# 2. SealedSecret を適用
kubectl apply -f k8s/secrets/atlantis/github-token.yaml

# 3. 復号化された Secret が作成されることを確認
kubectl get secret atlantis-github-token -n atlantis

# 4. Secret の内容を確認（復号化されている）
kubectl get secret atlantis-github-token -n atlantis -o jsonpath='{.data.token}' | base64 -d
```

### 6.7 secrets.tf の更新（Sealed Secrets 移行後）

Terraform から Secret を直接作成する代わりに、SealedSecret を使用するように変更します。

```hcl
# terraform/bootstrap/secrets.tf
# SealedSecret を使用する場合は、この手法でも構いません

# Option 1: Terraform で Secret を作成（Phase 2 のみ使用、Phase 3 以降は Sealed Secrets を使用）
resource "kubernetes_secret" "argocd_repo_creds" {
  metadata {
    name      = "repo-creds-bootstrap"
    namespace = kubernetes_namespace.argocd.metadata[0].name

    labels = {
      "argocd.argoproj.io/secret-type" = "repo-creds"
    }

    annotations = {
      "managed-by" = "terraform"
      "phase"      = "bootstrap-only"
    }
  }

  data = {
    type     = "git"
    url      = "https://github.com"
    username = var.github_username
    password = var.github_token
  }

  type = "Opaque"

  lifecycle {
    # Phase 3 で SealedSecret に移行する際に削除される
    ignore_changes = all
  }

  depends_on = [helm_release.argocd]
}

# Option 2: 環境変数から参照（推奨）
# terraform.tfvars に機密情報を書かずに、環境変数を使用
# 使用方法:
#   export TF_VAR_github_token="ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
#   terraform apply
```

---

## 7. Ingress と TLS 証明書管理

### 7.1 概要

NodePort を使用すると以下の問題があります：
- ポート番号を覚える必要がある（`:30443` など）
- ホスト名ベースのルーティングができない
- TLS 証明書の管理が煩雑

**解決策**: Ingress Controller（Traefik）+ cert-manager で統一的なアクセスを提供します。

### 7.2 Traefik Ingress Controller

#### Traefik アプリケーション

```yaml
# k8s/infra/traefik/traefik.yaml

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: traefik
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-2"
spec:
  project: default

  source:
    repoURL: https://traefik.github.io/charts
    chart: traefik
    targetRevision: 33.2.1
    helm:
      releaseName: traefik
      valuesObject:
        # LoadBalancer 経由でアクセス（MetalLB が IP を割り当て）
        service:
          type: LoadBalancer
          annotations:
            metallb.universe.tf/loadBalancerIPs: 192.168.1.200

        # Raspberry Pi 向けリソース制限
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi

        # ダッシュボード有効化
        ingressRoute:
          dashboard:
            enabled: true

        # ログレベル
        logs:
          general:
            level: INFO

        # ポート設定
        ports:
          web:
            port: 80
            exposedPort: 80
          websecure:
            port: 443
            exposedPort: 443
            # TLS を有効化
            tls:
              enabled: true

  destination:
    server: https://kubernetes.default.svc
    namespace: traefik

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

#### Traefik ミドルウェア（リダイレクト設定）

```yaml
# k8s/infra/traefik/resources/middleware.yaml

apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: redirect-https
  namespace: traefik
spec:
  redirectScheme:
    scheme: https
    permanent: true

---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: security-headers
  namespace: traefik
spec:
  headers:
    sslRedirect: true
    browserXssFilter: true
    contentTypeNosniff: true
    forceSTSHeader: true
    stsIncludeSubdomains: true
    stsPreload: true
    stsSeconds: 31536000
    frameDeny: true
```

#### Traefik リソースアプリケーション

```yaml
# k8s/infra/traefik/resources-app.yaml

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: traefik-resources
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
spec:
  project: default

  source:
    repoURL: https://github.com/YOUR_USERNAME/raspi-k8s-cluster.git
    targetRevision: main
    path: k8s/infra/traefik/resources

  destination:
    server: https://kubernetes.default.svc
    namespace: traefik

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### 7.3 cert-manager（TLS 証明書自動管理）

#### cert-manager アプリケーション

```yaml
# k8s/infra/cert-manager/cert-manager.yaml

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-3"
spec:
  project: default

  source:
    repoURL: https://charts.jetstack.io
    chart: cert-manager
    targetRevision: v1.16.3
    helm:
      releaseName: cert-manager
      valuesObject:
        # CRD を自動インストール
        crds:
          enabled: true

        # Raspberry Pi 向けリソース制限
        resources:
          requests:
            cpu: 50m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi

        webhook:
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi

        cainjector:
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: 200m
              memory: 256Mi

  destination:
    server: https://kubernetes.default.svc
    namespace: cert-manager

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

#### ClusterIssuer（自己署名証明書）

開発環境用に自己署名証明書を発行する Issuer を作成します。

```yaml
# k8s/infra/cert-manager/resources/cluster-issuer.yaml

apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}

---
# 開発環境用の CA 証明書
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: selfsigned-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: raspi-k8s-ca
  secretName: selfsigned-ca-secret
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
    group: cert-manager.io

---
# CA Issuer（この Issuer を使って実際の証明書を発行）
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ca-issuer
spec:
  ca:
    secretName: selfsigned-ca-secret
```

**本番環境の場合**: Let's Encrypt を使用します。

```yaml
# k8s/infra/cert-manager/resources/letsencrypt-issuer.yaml

apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    # Let's Encrypt 本番環境 URL
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - http01:
          ingress:
            class: traefik
```

#### cert-manager リソースアプリケーション

```yaml
# k8s/infra/cert-manager/resources-app.yaml

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager-resources
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-2"
spec:
  project: default

  source:
    repoURL: https://github.com/YOUR_USERNAME/raspi-k8s-cluster.git
    targetRevision: main
    path: k8s/infra/cert-manager/resources

  destination:
    server: https://kubernetes.default.svc
    namespace: cert-manager

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### 7.4 ArgoCD の Ingress 設定

NodePort の代わりに Ingress でアクセスできるようにします。

```yaml
# k8s/infra/argocd/ingress.yaml

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    # cert-manager が証明書を自動発行
    cert-manager.io/cluster-issuer: ca-issuer
    # HTTP から HTTPS にリダイレクト
    traefik.ingress.kubernetes.io/router.middlewares: traefik-redirect-https@kubernetescrd
    # Traefik で gRPC を有効化（ArgoCD CLI 用）
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - argocd.local
      secretName: argocd-tls-cert
  rules:
    - host: argocd.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 443
```

ArgoCD Application として管理：

```yaml
# k8s/infra/argocd/argocd-ingress-app.yaml

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd-ingress
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  project: default

  source:
    repoURL: https://github.com/YOUR_USERNAME/raspi-k8s-cluster.git
    targetRevision: main
    path: k8s/infra/argocd

  destination:
    server: https://kubernetes.default.svc
    namespace: argocd

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### 7.5 Atlantis の Ingress 設定

```yaml
# k8s/infra/atlantis/resources/ingress.yaml

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: atlantis
  namespace: atlantis
  annotations:
    cert-manager.io/cluster-issuer: ca-issuer
    traefik.ingress.kubernetes.io/router.middlewares: traefik-redirect-https@kubernetescrd
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - atlantis.local
      secretName: atlantis-tls-cert
  rules:
    - host: atlantis.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: atlantis
                port:
                  number: 80
```

ArgoCD Application として管理：

```yaml
# k8s/infra/atlantis/ingress-app.yaml

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: atlantis-ingress
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  project: default

  source:
    repoURL: https://github.com/YOUR_USERNAME/raspi-k8s-cluster.git
    targetRevision: main
    path: k8s/infra/atlantis/resources

  destination:
    server: https://kubernetes.default.svc
    namespace: atlantis

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### 7.6 ローカル DNS 設定

Ingress でホスト名ベースのルーティングを使用するため、ローカルマシンに DNS エントリを追加します。

```bash
# /etc/hosts を編集（macOS/Linux）
sudo nano /etc/hosts

# 以下を追加（MetalLB で割り当てた IP を使用）
192.168.1.200  argocd.local
192.168.1.200  atlantis.local
192.168.1.200  traefik.local

# Windows の場合
# C:\Windows\System32\drivers\etc\hosts を管理者権限で編集
```

### 7.7 アクセス確認

```bash
# 1. Traefik の IP を確認
kubectl get svc -n traefik

# 2. ブラウザでアクセス
# ArgoCD:   https://argocd.local
# Atlantis: https://atlantis.local
# Traefik:  https://traefik.local/dashboard/

# 3. 証明書警告が出る場合
# 自己署名証明書を使用しているため、ブラウザで「詳細設定」→「続行」を選択
```

---

## 8. デプロイ手順（完全版）

### 8.1 事前準備

```bash
# 1. リポジトリをクローン
git clone https://github.com/kta/raspi-k8s-cluster.git
cd raspi-k8s-cluster

# 2. kubeseal をインストール
brew install kubeseal  # macOS

# 3. terraform.tfvars を作成
cp terraform/bootstrap/terraform.tfvars.example terraform/bootstrap/terraform.tfvars
# エディタで編集して GitHub 情報を入力

# 4. .gitignore を確認
echo "terraform/bootstrap/terraform.tfvars" >> .gitignore
git add .gitignore
git commit -m "Add terraform.tfvars to gitignore"
```

### 8.2 Phase 2: Terraform で基盤をインストール

```bash
# Terraform 初期化
make terraform-init

# 実行計画を確認
make terraform-plan

# 適用（ArgoCD + Sealed Secrets Controller をインストール）
make terraform-apply

# ArgoCD が起動するまで待機
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
```

### 8.3 Secret の暗号化と登録

```bash
# 1. ArgoCD リポジトリ認証情報を暗号化
kubectl create secret generic repo-creds \
  --from-literal=type=git \
  --from-literal=url=https://github.com \
  --from-literal=username=kta \
  --from-literal=password=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
  --namespace argocd \
  --dry-run=client -o yaml | \
kubectl label -f - --local -o yaml \
  argocd.argoproj.io/secret-type=repo-creds | \
kubeseal --format yaml \
  --controller-name sealed-secrets \
  --controller-namespace kube-system \
  > k8s/secrets/argocd/repo-creds.yaml

# 2. Atlantis GitHub Token を暗号化
kubectl create secret generic atlantis-github-token \
  --from-literal=token=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
  --namespace atlantis \
  --dry-run=client -o yaml | \
kubeseal --format yaml \
  --controller-name sealed-secrets \
  --controller-namespace kube-system \
  > k8s/secrets/atlantis/github-token.yaml

# 3. Git にコミット
git add k8s/secrets/
git commit -m "Add encrypted secrets"
git push origin main
```

### 8.4 Phase 3: GitOps で全コンポーネントをデプロイ

```bash
# 1. YOUR_USERNAME を自分のユーザー名に置換
find k8s -name "*.yaml" -exec sed -i '' 's/YOUR_USERNAME/your-actual-username/g' {} \;

# 2. MetalLB の IP レンジを環境に合わせて変更
# 実機: 192.168.1.200-192.168.1.220
# Vagrant: 192.168.56.200-192.168.56.220
vim k8s/infra/metallb/resources/ip-pool.yaml

# 3. Git にコミット
git add k8s/
git commit -m "Add GitOps manifests for Phase 3"
git push origin main

# 4. Root Application を適用
make argocd-bootstrap

# 5. 同期を待機（5-10分かかる場合があります）
watch kubectl get applications -n argocd
```

### 8.5 /etc/hosts の設定

```bash
# Traefik の External IP を確認
TRAEFIK_IP=$(kubectl get svc traefik -n traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo $TRAEFIK_IP

# /etc/hosts に追加
sudo tee -a /etc/hosts << EOF
${TRAEFIK_IP}  argocd.local
${TRAEFIK_IP}  atlantis.local
${TRAEFIK_IP}  traefik.local
EOF
```

### 8.6 動作確認

```bash
# 1. すべてのアプリケーションが Synced かつ Healthy であることを確認
kubectl get applications -n argocd

# 2. ArgoCD にブラウザでアクセス
# URL: https://argocd.local
# ユーザー名: admin
# パスワード:
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d

# 3. Atlantis にアクセス
# URL: https://atlantis.local

# 4. Traefik Dashboard にアクセス
# URL: https://traefik.local/dashboard/
```

---

## 9. 検証

### 9.1 全コンポーネントの確認

```bash
# ArgoCD アプリケーション
kubectl get applications -n argocd

# 各コンポーネントの Pod
kubectl get pods -n kube-flannel  # CNI
kubectl get pods -n metallb-system  # MetalLB
kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets  # Sealed Secrets
kubectl get pods -n cert-manager  # cert-manager
kubectl get pods -n traefik  # Traefik
kubectl get pods -n atlantis  # Atlantis
```

### 9.2 Ingress と証明書の確認

```bash
# Ingress リソース
kubectl get ingress -A

# 証明書の自動発行を確認
kubectl get certificate -A

# Certificate が Ready になるまで待機
kubectl wait --for=condition=ready certificate argocd-tls-cert -n argocd --timeout=120s
kubectl wait --for=condition=ready certificate atlantis-tls-cert -n atlantis --timeout=120s
```

### 9.3 Sealed Secrets の動作確認

```bash
# SealedSecret が復号化されて Secret が作成されていることを確認
kubectl get sealedsecrets -A
kubectl get secrets -A | grep -E "argocd|atlantis"

# Secret の内容を確認（復号化されている）
kubectl get secret repo-creds -n argocd -o jsonpath='{.data.password}' | base64 -d
```

### 9.4 MetalLB のテスト

```bash
# テスト用 Service を作成
kubectl create deployment test-nginx --image=nginx
kubectl expose deployment test-nginx --port=80 --type=LoadBalancer

# External IP が割り当てられることを確認
kubectl get svc test-nginx -w

# アクセステスト
NGINX_IP=$(kubectl get svc test-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl http://${NGINX_IP}

# クリーンアップ
kubectl delete deployment test-nginx
kubectl delete svc test-nginx
```

---

## 10. トラブルシューティング

### Sealed Secrets Controller が Secret を復号化しない

```bash
# Controller のログを確認
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets

# SealedSecret の状態を確認
kubectl describe sealedsecret <name> -n <namespace>

# 公開鍵が正しいか確認
kubeseal --fetch-cert \
  --controller-name sealed-secrets \
  --controller-namespace kube-system

# 再暗号化が必要な場合
kubectl create secret generic <name> \
  --from-literal=key=value \
  --namespace <namespace> \
  --dry-run=client -o yaml | \
kubeseal --format yaml > sealed-secret.yaml
kubectl apply -f sealed-secret.yaml
```

### Traefik が LoadBalancer IP を取得しない

```bash
# MetalLB が正常に動作しているか確認
kubectl get pods -n metallb-system
kubectl logs -n metallb-system -l component=speaker

# IPAddressPool が正しく設定されているか確認
kubectl describe ipaddresspool -n metallb-system

# Service の状態を確認
kubectl describe svc traefik -n traefik

# IP を手動で指定（metallb.universe.tf/loadBalancerIPs アノテーション）
kubectl patch svc traefik -n traefik -p '{"metadata":{"annotations":{"metallb.universe.tf/loadBalancerIPs":"192.168.1.200"}}}'
```

### cert-manager が証明書を発行しない

```bash
# Certificate の状態を確認
kubectl describe certificate <name> -n <namespace>

# CertificateRequest の状態を確認
kubectl get certificaterequest -n <namespace>
kubectl describe certificaterequest <name> -n <namespace>

# cert-manager のログを確認
kubectl logs -n cert-manager -l app=cert-manager

# ClusterIssuer が正しく設定されているか確認
kubectl describe clusterissuer ca-issuer

# 証明書を手動で再発行
kubectl delete certificate <name> -n <namespace>
# ArgoCD が自動的に再作成します
```

### Ingress でアクセスできない

```bash
# Ingress リソースが正しく作成されているか確認
kubectl describe ingress <name> -n <namespace>

# Traefik の IngressRoute を確認
kubectl get ingressroute -n traefik

# Traefik のログを確認
kubectl logs -n traefik -l app.kubernetes.io/name=traefik

# /etc/hosts の設定を確認
cat /etc/hosts | grep -E "argocd|atlantis|traefik"

# DNS 解決をテスト
nslookup argocd.local
ping argocd.local

# TLS 証明書を確認
openssl s_client -connect argocd.local:443 -servername argocd.local
```

### ArgoCD が SealedSecret を同期しない

```bash
# Application の状態を確認
kubectl describe application sealed-secrets -n argocd

# ArgoCD がリポジトリにアクセスできるか確認
argocd repo list

# SealedSecret が正しい Namespace に作成されているか確認
kubectl get sealedsecrets -A

# 手動で同期を実行
argocd app sync sealed-secrets

# ArgoCD Application Controller のログを確認
kubectl logs -n argocd -l app.kubernetes.io/component=application-controller
```

---

## 11. セキュリティのベストプラクティス

### 11.1 Secret 管理

1. **Terraform に機密情報を書かない**
   - 環境変数を使用: `export TF_VAR_github_token="..."`
   - Sealed Secrets で Git 管理
   - Phase 2 では最小限の Secret のみ Terraform で作成し、Phase 3 以降は Sealed Secrets に移行

2. **terraform.tfvars を Git にコミットしない**
   ```bash
   echo "terraform/bootstrap/terraform.tfvars" >> .gitignore
   ```

3. **Secret のローテーション**
   ```bash
   # GitHub Token を更新した場合
   # 1. 新しい Token で SealedSecret を再作成
   kubectl create secret generic repo-creds \
     --from-literal=password=NEW_TOKEN \
     --namespace argocd \
     --dry-run=client -o yaml | \
   kubeseal --format yaml > k8s/secrets/argocd/repo-creds.yaml

   # 2. Git にコミットして ArgoCD が自動同期
   git add k8s/secrets/argocd/repo-creds.yaml
   git commit -m "Rotate GitHub token"
   git push origin main
   ```

### 11.2 Ingress セキュリティ

1. **HTTPS 強制リダイレクト**
   - Traefik Middleware で HTTP → HTTPS リダイレクト

2. **セキュリティヘッダー**
   - X-Frame-Options, X-XSS-Protection, HSTS など

3. **Basic 認証（オプション）**
   ```yaml
   # k8s/infra/traefik/resources/basic-auth.yaml
   apiVersion: traefik.io/v1alpha1
   kind: Middleware
   metadata:
     name: basic-auth
     namespace: traefik
   spec:
     basicAuth:
       secret: basic-auth-secret
   ---
   # htpasswd で作成したユーザー・パスワードを Secret に保存
   # htpasswd -c auth admin
   # kubectl create secret generic basic-auth-secret --from-file=users=auth -n traefik
   ```

### 11.3 RBAC（Role-Based Access Control）

ArgoCD と Atlantis に適切な権限を付与します。

```yaml
# k8s/infra/argocd/rbac-config.yaml

apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.csv: |
    # 管理者には全権限
    g, admin, role:admin

    # 開発者には読み取り専用権限
    p, role:developer, applications, get, */*, allow
    p, role:developer, applications, sync, */*, allow

  policy.default: role:readonly
```

---

## 12. まとめ

### 完成したアーキテクチャ

```
┌─────────────────────────────────────────────────────────────────────┐
│                         セキュアな GitOps 環境                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────┐   ┌────────────┐   ┌──────────────────────────────┐  │
│  │ GitHub  │──▶│   ArgoCD   │──▶│    Kubernetes Cluster        │  │
│  │  Repo   │   │            │   │                              │  │
│  └─────────┘   └────────────┘   │  ┌────────────────────────┐  │  │
│       │               │          │  │  Sealed Secrets Ctrl   │  │  │
│       │  SealedSecret │          │  │  (Secret 自動復号化)    │  │  │
│       │  (暗号化済み)   │          │  └────────────────────────┘  │  │
│       │               ▼          │                              │  │
│       │        ┌──────────────┐  │  ┌────────────────────────┐  │  │
│       │        │ Applications │  │  │  Traefik (LoadBalancer)│  │  │
│       │        ├──────────────┤  │  │  MetalLB: 192.168.1.200│  │  │
│       │        │ - CNI        │  │  └────────┬───────────────┘  │  │
│       │        │ - MetalLB    │  │           │                  │  │
│       │        │ - Traefik    │  │  ┌────────▼───────────────┐  │  │
│       │        │ - cert-mgr   │  │  │  cert-manager (TLS)    │  │  │
│       │        │ - Atlantis   │  │  └────────────────────────┘  │  │
│       │        └──────────────┘  │           │                  │  │
│       │                          │           ▼                  │  │
│       │                          │  https://argocd.local        │  │
│       │                          │  https://atlantis.local      │  │
│       │                          │                              │  │
│       └────── Atlantis (PR経由でTerraform実行) ◀────────────────┤  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 達成した改善点

| 従来の課題 | 解決策 | 効果 |
|-----------|--------|------|
| Secret を Git に保存できない | Sealed Secrets | 暗号化して安全に Git 管理 |
| Terraform にパスワードを書きたくない | 環境変数 + Sealed Secrets | 機密情報をコードから分離 |
| NodePort でのアクセスが不便 | Traefik Ingress | ホスト名ベースの統一アクセス |
| TLS 証明書の管理が煩雑 | cert-manager | 自動発行・更新 |

### 次のステップ

Phase 4 では、実際のアプリケーションを ArgoCD で管理します。

```bash
# Phase 4 のドキュメントを参照
cat docs/PHASE4_APP_DEPLOYMENT.md
```

---

以上で Phase 2 & 3 のセットアップが完了です。
