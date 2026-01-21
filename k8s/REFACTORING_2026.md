# Kubernetes Structure Refactoring (2026-01)

## 概要

このリファクタリングでは、k8sディレクトリ構造を以下のように変更しました：

1. **インフラのレイヤー化** - 機能別に00-04の5層構造に整理
2. **Kustomize→Helm移行** - 可能な限りPure Helm構成に移行
3. **アプリケーション構造の刷新** - Pure Helmチャートのみで管理

## 新しいディレクトリ構造

```
k8s/
├── bootstrap/
│   ├── root.yaml                    # ApplicationSet (Terraform管理)
│   ├── values/                      # 環境パラメータ
│   └── HELM_SUPPORT_PROPOSAL.yaml   # Helm対応提案（NEW）
│
├── infrastructure/
│   ├── 00-argocd-apps/             # Control Plane (Layer 0)
│   │   └── argocd-apps/            # ArgoCD Application定義
│   │
│   ├── 01-system/                  # Core System (Layer 1)
│   │   └── cni/                    # Pod networking
│   │
│   ├── 02-network/                 # Network & Ingress (Layer 2)
│   │   ├── metallb/
│   │   ├── traefik/
│   │   ├── cert-manager/
│   │   └── cert-manager-resources/
│   │
│   ├── 03-observability/           # Observability (Layer 3)
│   │   ├── monitoring-config/
│   │   ├── monitoring-nodeports/
│   │   └── grafana/
│   │
│   └── 04-ops/                     # Operations (Layer 4)
│       ├── atlantis/
│       └── argocd/
│
└── applications/                    # User Applications
    ├── README.md
    ├── _example/
    └── my-app/                     # Pure Helmサンプル (NEW)
        ├── Chart.yaml
        ├── values.yaml
        ├── values-prod.yaml
        ├── values-vagrant.yaml
        ├── README.md
        └── templates/
            ├── deployment.yaml      # sync-wave付き
            ├── service.yaml
            └── sealed-secret.yaml   # SealedSecret対応
```

## 主な変更点

### 1. インフラのレイヤー化

**Before:**
```
infrastructure/
├── argocd/
├── argocd-apps/
├── atlantis/
├── cni/
├── metallb/
└── ...
```

**After:**
```
infrastructure/
├── 00-argocd-apps/    # Control Plane
├── 01-system/         # Core System
├── 02-network/        # Network & Ingress
├── 03-observability/  # Monitoring
└── 04-ops/            # Operations Tools
```

**メリット:**
- 依存関係が明確
- デプロイ順序が視覚的に理解しやすい
- 新規コンポーネントの配置場所が明確

### 2. Pure Helm構成

**Before (Kustomize):**
```
my-app/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   └── service.yaml
└── overlays/
    ├── production/
    │   └── kustomization.yaml
    └── vagrant/
        └── kustomization.yaml
```

**After (Pure Helm):**
```
my-app/
├── Chart.yaml
├── values.yaml              # 共通設定
├── values-prod.yaml         # 本番環境設定
├── values-vagrant.yaml      # Vagrant環境設定
└── templates/
    ├── deployment.yaml      # sync-wave付き
    ├── service.yaml
    └── sealed-secret.yaml
```

**メリット:**
- Kustomizeの複雑さを排除
- 環境差分がvaluesファイルで明確
- Helmのエコシステムを活用可能
- テンプレート化が容易

### 3. SealedSecret統合

暗号化されたシークレットを`values-*.yaml`に直接埋め込み：

```yaml
# values-prod.yaml
sealedSecret:
  enabled: true
  encryptedData:
    password: "AgBy3i4OJSWK+PiTySYZZA9rO43cGDEq..."
    api-key: "AgAR7bDj8fKLmNoPqRsTuVwXyZ..."
```

```yaml
# templates/sealed-secret.yaml
{{- if .Values.sealedSecret.enabled -}}
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: {{ include "my-app.fullname" . }}
spec:
  encryptedData:
    {{- toYaml .Values.sealedSecret.encryptedData | nindent 4 }}
{{- end }}
```

## 移行手順

### 1. バックアップ

```bash
cd /Users/spm/Documents/workspace/myspace/raspi-k8s-cluster
git add -A && git commit -m "Backup before k8s refactoring"
```

### 2. インフラ移行

```bash
cd k8s
bash migrate_infrastructure.sh
```

### 3. Bootstrap更新

`k8s/bootstrap/HELM_SUPPORT_PROPOSAL.yaml`を参照し、Terraform設定を更新：
- `terraform/modules/argocd/applicationset.tf`
- Helm対応のmatrix generatorを追加

### 4. 検証

```bash
# Helmチャート検証
cd k8s/applications/my-app
helm lint .
helm template test . -f values-vagrant.yaml

# 完全環境再構築
cd /Users/spm/Documents/workspace/myspace/raspi-k8s-cluster
make setup-all-vagrant
```

## 新しいアプリケーションの追加方法

### 1. Helmチャート作成

```bash
cd k8s/applications
helm create your-app
```

### 2. カスタマイズ

```bash
cd your-app

# Chart.yamlを編集
vim Chart.yaml

# 環境別valuesを作成
cp values.yaml values-prod.yaml
cp values.yaml values-vagrant.yaml

# テンプレートにsync-wave追加
vim templates/deployment.yaml
```

### 3. SealedSecret追加（必要な場合）

```bash
# templates/sealed-secret.yamlを作成
cat > templates/sealed-secret.yaml <<'EOF'
{{- if .Values.sealedSecret.enabled -}}
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: {{ include "your-app.fullname" . }}
spec:
  encryptedData:
    {{- toYaml .Values.sealedSecret.encryptedData | nindent 4 }}
{{- end }}
EOF

# 暗号化データを生成
echo -n "your-secret" | kubeseal --raw \
  --from-file=/dev/stdin \
  --namespace default \
  --name your-app

# values-prod.yamlに追加
vim values-prod.yaml
```

### 4. デプロイ

```bash
git add . && git commit -m "Add your-app" && git push
```

ArgoCDが自動的に検出してデプロイします。

## トラブルシューティング

### 移行スクリプトが失敗する

```bash
# ドライランで確認
bash migrate_infrastructure.sh --dry-run

# ロールバック
rm -rf k8s/infrastructure
mv k8s/.migration_backup_*/infrastructure k8s/
```

### Helmチャートがlintエラー

```bash
# エラー詳細を確認
helm lint . --debug

# テンプレート出力を確認
helm template test . -f values-vagrant.yaml --debug
```

### ArgoCDが検出しない

Bootstrap ApplicationSetのHelm対応が必要です。
`k8s/bootstrap/HELM_SUPPORT_PROPOSAL.yaml`を参照してTerraform設定を更新してください。

## 参考資料

- [my-app README](../applications/my-app/README.md) - サンプルアプリケーション
- [Helm Documentation](https://helm.sh/docs/)
- [ArgoCD ApplicationSet](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/)
- [SealedSecrets](https://github.com/bitnami-labs/sealed-secrets)
