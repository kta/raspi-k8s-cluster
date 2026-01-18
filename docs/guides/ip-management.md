# 環境別IP管理ガイド

このガイドでは、実機（production）とVagrant環境で異なるIPアドレスを自動的に使い分ける仕組みを説明します。

## 🎯 概要

プロジェクトは2つの環境で異なるIPレンジを自動管理します：

| 環境 | ノードIP | VIP | MetalLB | Ingress IP |
|------|---------|-----|---------|-----------|
| **production** | 192.168.1.101-103 | 192.168.1.100 | 192.168.1.200-220 | 192.168.1.200 |
| **vagrant** | 192.168.56.101-103 | 192.168.56.100 | 192.168.56.200-220 | 192.168.56.200 |

## 🏗️ アーキテクチャ

### 変数の流れ

```
┌─────────────────────────────────────┐
│ 1. Ansible Inventory (真実の源)     │
│    inventory.ini / inventory_vagrant.ini │
│    - environment=production/vagrant │
│    - metallb_ip_range=...           │
│    - ingress_ip=...                 │
│    - vip=...                        │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ 2. generate_tfvars.sh               │
│    インベントリ → Terraform変数変換 │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ 3. Terraform (bootstrap)            │
│    terraform.auto.tfvars            │
│    → ArgoCDをデプロイ               │
│    → ConfigMapで環境設定を保存      │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ 4. patch_argocd_apps.sh             │
│    ArgoCD Application更新           │
│    → 環境別overlayパスを指定        │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ 5. Kustomize Overlays               │
│    metallb/overlays/production/     │
│    metallb/overlays/vagrant/        │
│    → 環境別IPレンジをパッチ適用     │
└─────────────────────────────────────┘
```

## 📋 設定方法

### 1. Ansible インベントリ

**真実の源**として、すべてのIP設定をインベントリファイルで管理：

#### production環境 (`ansible/inventory/inventory.ini`)
```ini
[all:vars]
ansible_user=pi
k8s_version=1.35
vip=192.168.1.100
interface=eth0
haproxy_port=8443
node_ips=192.168.1.101,192.168.1.102,192.168.1.103

# 環境固有の設定
environment=production
metallb_ip_range=192.168.1.200-192.168.1.220
ingress_ip=192.168.1.200
```

#### vagrant環境 (`ansible/inventory/inventory_vagrant.ini`)
```ini
[all:vars]
ansible_user=vagrant
k8s_version=1.35
vip=192.168.56.100
interface=eth1
haproxy_port=8443
node_ips=192.168.56.101,192.168.56.102,192.168.56.103

# 環境固有の設定
environment=vagrant
metallb_ip_range=192.168.56.200-192.168.56.220
ingress_ip=192.168.56.200
```

### 2. 自動変数生成

```bash
# production環境
make generate-tfvars ENV=production

# vagrant環境
make generate-tfvars ENV=vagrant
```

これにより `terraform/bootstrap/terraform.auto.tfvars` が自動生成されます：

```hcl
environment      = "production"
vip              = "192.168.1.100"
metallb_ip_range = "192.168.1.200-192.168.1.220"
ingress_ip       = "192.168.1.200"

# GitHub設定は terraform.tfvars から継承
```

### 3. ArgoCD Application更新

```bash
# production環境
make patch-argocd-apps ENV=production

# vagrant環境
make patch-argocd-apps ENV=vagrant
```

これにより `k8s/infra/metallb/config.yaml` のパスが更新されます：

```yaml
# production の場合
spec:
  source:
    path: k8s/infra/metallb/overlays/production

# vagrant の場合
spec:
  source:
    path: k8s/infra/metallb/overlays/vagrant
```

## 📦 Kustomize構造

MetalLBの設定は以下の構造で管理：

```
k8s/infra/metallb/
├── base/
│   ├── kustomization.yaml
│   ├── metallb.yaml           # MetalLB本体
│   └── ip-pool.yaml           # IPAddressPool (プレースホルダー)
├── overlays/
│   ├── production/
│   │   └── kustomization.yaml # 192.168.1.200-220 にパッチ
│   └── vagrant/
│       └── kustomization.yaml # 192.168.56.200-220 にパッチ
├── metallb.yaml               # ArgoCD Application (本体)
└── config.yaml                # ArgoCD Application (設定)
```

### overlay の例

**production** (`overlays/production/kustomization.yaml`):
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: metallb-system

bases:
  - ../../base

patches:
  - target:
      kind: IPAddressPool
      name: default-pool
    patch: |-
      - op: replace
        path: /spec/addresses/0
        value: 192.168.1.200-192.168.1.220
```

**vagrant** (`overlays/vagrant/kustomization.yaml`):
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: metallb-system

bases:
  - ../../base

patches:
  - target:
      kind: IPAddressPool
      name: default-pool
    patch: |-
      - op: replace
        path: /spec/addresses/0
        value: 192.168.56.200-192.168.56.220
```

## 🚀 デプロイワークフロー

### 実機環境

```bash
# 一括実行（推奨）
make setup-all ENV=production

# または個別実行
make generate-tfvars ENV=production
make patch-argocd-apps ENV=production
make ansible-setup
make fetch-kubeconfig
make terraform-apply ENV=production
make argocd-bootstrap
```

### Vagrant環境

```bash
# 一括実行（推奨）
make setup-all-vagrant

# または個別実行
make generate-tfvars ENV=vagrant
make patch-argocd-apps ENV=vagrant
make vagrant-up
make ansible-setup-vagrant
make fetch-kubeconfig-vagrant
make terraform-apply ENV=vagrant
make argocd-bootstrap
```

## 🔍 検証

### 環境設定の確認

```bash
# Makefile環境設定
make env-info ENV=production

# Terraform変数
cat terraform/bootstrap/terraform.auto.tfvars

# Kubernetes ConfigMap
kubectl get configmap -n argocd environment-config -o yaml
```

### MetalLB設定の確認

```bash
# IPAddressPool
kubectl get ipaddresspool -n metallb-system default-pool -o yaml

# LoadBalancer Service
kubectl get svc -A --field-selector spec.type=LoadBalancer

# 期待される出力（production）:
# traefik   traefik   LoadBalancer   10.96.0.1   192.168.1.200   80:30080/TCP,443:30443/TCP
```

### ArgoCD Application確認

```bash
# MetalLB config の overlay パス確認
kubectl get application -n argocd metallb-config -o jsonpath='{.spec.source.path}'

# 期待される出力:
# production: k8s/infra/metallb/overlays/production
# vagrant: k8s/infra/metallb/overlays/vagrant
```

## 🛠️ トラブルシューティング

### 問題: terraform.auto.tfvars が環境と不一致

**症状**: Vagrant環境なのに production の設定が使われている

**解決策**:
```bash
# 検証スクリプトで確認
./scripts/verify_tfvars_environment.sh vagrant

# 自動修正
make generate-tfvars ENV=vagrant

# 手動削除して再生成
rm terraform/bootstrap/terraform.auto.tfvars
make generate-tfvars ENV=vagrant
```

### 問題: MetalLBが間違ったIPレンジを使用

**症状**: LoadBalancer ServiceにIPが割り当てられない

**解決策**:
```bash
# ArgoCD Application を手動同期
argocd app sync metallb-config

# IPAddressPool を確認
kubectl get ipaddresspool -n metallb-system default-pool -o yaml

# 必要に応じて overlay を修正
vim k8s/infra/metallb/overlays/production/kustomization.yaml
```

### 問題: 環境切り替え後に古い設定が残る

**症状**: 環境を切り替えたが、ArgoCDが古いパスを参照

**解決策**:
```bash
# ArgoCD Application を再適用
make patch-argocd-apps ENV=production
kubectl apply -f k8s/bootstrap/root-app.yaml

# すべてのアプリを同期
argocd app sync --async --prune --self-heal -l app.kubernetes.io/instance=root
```

## 📝 IP設定変更手順

IPアドレスを変更する場合の手順：

```bash
# 1. インベントリファイルを編集
vim ansible/inventory/inventory.ini
# vip, metallb_ip_range, ingress_ip を変更

# 2. Terraform変数を再生成
make generate-tfvars ENV=production

# 3. ArgoCD Application を更新
make patch-argocd-apps ENV=production

# 4. Terraform を再実行
cd terraform/bootstrap && terraform apply

# 5. ArgoCD を同期
kubectl apply -f k8s/bootstrap/root-app.yaml
argocd app sync metallb-config
```

## 🆕 新しい環境の追加

staging 環境などを追加する場合：

### 1. インベントリファイル作成

```bash
cp ansible/inventory/inventory.ini ansible/inventory/inventory_staging.ini
vim ansible/inventory/inventory_staging.ini
# environment=staging
# IPアドレスを変更
```

### 2. Kustomize overlay作成

```bash
mkdir -p k8s/infra/metallb/overlays/staging
cp k8s/infra/metallb/overlays/production/kustomization.yaml \
   k8s/infra/metallb/overlays/staging/
vim k8s/infra/metallb/overlays/staging/kustomization.yaml
# IPレンジを変更
```

### 3. スクリプト更新

- `scripts/generate_tfvars.sh`: 環境検出に staging を追加
- `scripts/patch_argocd_apps.sh`: staging を許可
- `terraform/bootstrap/variables.tf`: validation に staging を追加

### 4. Makefile更新

```makefile
.PHONY: setup-all-staging
setup-all-staging: ## 全フェーズを実行（staging環境）
	@echo "🚀 staging環境のセットアップを開始..."
	$(MAKE) env-info ENV=staging
	$(MAKE) generate-tfvars ENV=staging
	$(MAKE) patch-argocd-apps ENV=staging
	# ...
```

## 🎯 ベストプラクティス

### ✅ すべきこと

1. **インベントリファイルを真実の源とする**
   - すべてのIP設定はインベントリで管理
   - 変更時は必ず `make generate-tfvars` を実行

2. **環境を明示的に指定**
   ```bash
   make terraform-apply ENV=production
   ```

3. **変更前に検証**
   ```bash
   make env-info ENV=production
   make validate-setup ENV=production
   ```

### ❌ すべきでないこと

1. **マニフェストに直接IPを書かない**
   - Kustomize overlay を使用

2. **terraform.auto.tfvars を手動編集しない**
   - 自動生成ファイルなので上書きされる
   - インベントリファイルを編集する

3. **環境を混在させない**
   - 1つのクラスタ = 1つの環境

## 📚 関連ドキュメント

- [クイックスタート](./quickstart.md) - 基本的なセットアップ手順
- [サービスアクセス](./service-access.md) - ArgoCD/Atlantisへのアクセス方法
- [トラブルシューティング](./troubleshooting.md) - よくある問題と解決策
