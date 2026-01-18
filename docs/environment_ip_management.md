# 環境別IP管理ガイド

このドキュメントでは、実機（production）とVagrant環境で異なるIPアドレスを使用するための設定方法を説明します。

## 📋 概要

プロジェクトは以下の2つの環境をサポートします：

| 環境 | 識別子 | ノードIP範囲 | VIP | MetalLB IP範囲 | Ingress IP |
|------|--------|-------------|-----|---------------|-----------|
| **実機** | `production` | 192.168.1.101-103 | 192.168.1.100 | 192.168.1.200-220 | 192.168.1.200 |
| **Vagrant** | `vagrant` | 192.168.56.101-103 | 192.168.56.100 | 192.168.56.200-220 | 192.168.56.200 |

## 🏗️ アーキテクチャ

### 変数の流れ

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Ansible Inventory (真実の源)                             │
│    - ansible/inventory/inventory.ini (production)           │
│    - ansible/inventory/inventory_vagrant.ini (vagrant)      │
│                                                             │
│    変数定義:                                                │
│      environment=production                                 │
│      metallb_ip_range=192.168.1.200-192.168.1.220           │
│      ingress_ip=192.168.1.200                               │
│      vip=192.168.1.100                                      │
└──────────────┬──────────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. 自動変換スクリプト                                        │
│    scripts/generate_tfvars.sh                               │
│                                                             │
│    インベントリから変数を抽出し、                            │
│    terraform.auto.tfvars を生成                             │
└──────────────┬──────────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. Terraform (Phase 2)                                      │
│    terraform/bootstrap/terraform.auto.tfvars                │
│                                                             │
│    変数を使用してArgoCDをデプロイ                            │
│    環境設定をConfigMapとして保存                             │
└──────────────┬──────────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. Kustomize Overlays (Phase 3)                             │
│    k8s/infra/metallb/overlays/production/                   │
│    k8s/infra/metallb/overlays/vagrant/                      │
│                                                             │
│    環境別のIPレンジをパッチとして適用                        │
└─────────────────────────────────────────────────────────────┘
```

## 🔧 設定方法

### 1. Ansible インベントリファイルの設定

**実機環境** (`ansible/inventory/inventory.ini`):
```ini
[all:vars]
k8s_version=1.35
vip=192.168.1.100
interface=eth0
haproxy_port=8443
node_ips=192.168.1.101,192.168.1.102,192.168.1.103

# MetalLB / LoadBalancer設定
metallb_ip_range=192.168.1.200-192.168.1.220
environment=production
ingress_ip=192.168.1.200
```

**Vagrant環境** (`ansible/inventory/inventory_vagrant.ini`):
```ini
[all:vars]
k8s_version=1.35
vip=192.168.56.100
interface=eth1
haproxy_port=8443
node_ips=192.168.56.101,192.168.56.102,192.168.56.103

# MetalLB / LoadBalancer設定
metallb_ip_range=192.168.56.200-192.168.56.220
environment=vagrant
ingress_ip=192.168.56.200
```

### 2. Terraform 変数の自動生成

インベントリから Terraform 変数を自動生成：

```bash
# 実機環境
make generate-tfvars ENV=production

# Vagrant環境
make generate-tfvars ENV=vagrant
```

これにより `terraform/bootstrap/terraform.auto.tfvars` が生成されます。

### 3. ArgoCD Application マニフェストの更新

環境に応じて ArgoCD の Application マニフェストを更新：

```bash
# 実機環境
make patch-argocd-apps ENV=production

# Vagrant環境
make patch-argocd-apps ENV=vagrant
```

これにより、MetalLB の `config.yaml` が適切な overlay パスに更新されます。

## 📦 Kustomize構造

MetalLBの設定は以下の構造で管理されます：

```
k8s/infra/metallb/
├── base/
│   ├── kustomization.yaml
│   ├── kustomizeconfig.yaml
│   ├── metallb.yaml
│   └── ip-pool.yaml          # プレースホルダー
├── overlays/
│   ├── production/
│   │   └── kustomization.yaml  # 192.168.1.200-220
│   └── vagrant/
│       └── kustomization.yaml  # 192.168.56.200-220
├── config.yaml                 # ArgoCD Application
└── metallb.yaml                # ArgoCD Application (本体)
```

### overlay の例

**production** (`k8s/infra/metallb/overlays/production/kustomization.yaml`):
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

**vagrant** (`k8s/infra/metallb/overlays/vagrant/kustomization.yaml`):
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

### 実機環境へのデプロイ

```bash
# 1. 環境変数を自動生成
make generate-tfvars ENV=production
make patch-argocd-apps ENV=production

# 2. Phase 1: Ansible でクラスタ構築
make ansible-setup

# 3. kubeconfig取得
make fetch-kubeconfig

# 4. Phase 2: Terraform で ArgoCD インストール
make terraform-apply

# 5. Phase 3: ArgoCD でインフラをデプロイ
make argocd-bootstrap

# または一括実行
make setup-all ENV=production
```

### Vagrant環境へのデプロイ

```bash
# すべて自動化されています
make ansible-setup-vagrant
make fetch-kubeconfig-vagrant
make terraform-apply ENV=vagrant
make argocd-bootstrap
```

## 🔍 検証

### 環境設定の確認

```bash
# Makefile の環境設定を表示
make env-info ENV=production
make env-info ENV=vagrant

# Terraform変数の確認
cat terraform/bootstrap/terraform.auto.tfvars

# Kubernetes ConfigMap の確認
kubectl get configmap -n argocd environment-config -o yaml
```

### MetalLB IPアドレスプールの確認

```bash
# IPAddressPool を確認
kubectl get ipaddresspool -n metallb-system default-pool -o yaml

# LoadBalancer サービスの IP を確認
kubectl get svc -A --field-selector spec.type=LoadBalancer
```

### ArgoCD Application の確認

```bash
# MetalLB Applicationのパスを確認
kubectl get application -n argocd metallb-config -o jsonpath='{.spec.source.path}'

# 期待される出力:
# production: k8s/infra/metallb/overlays/production
# vagrant: k8s/infra/metallb/overlays/vagrant
```

## 🛠️ トラブルシューティング

### 問題: IPアドレスがハードコードされている

**症状**: マニフェストに `192.168.1.200` などがハードコードされている

**解決策**:
```bash
# インベントリファイルを更新
vim ansible/inventory/inventory.ini

# Terraform変数を再生成
make generate-tfvars ENV=production

# ArgoCD Applicationを再適用
make patch-argocd-apps ENV=production

# Terraformを再実行
cd terraform/bootstrap && terraform apply
```

### 問題: 環境が混在している

**症状**: Vagrant環境なのに production の IP が使われている

**解決策**:
```bash
# 環境を明示的に指定
make generate-tfvars ENV=vagrant
make patch-argocd-apps ENV=vagrant

# ArgoCD を手動で同期
argocd app sync metallb-config
```

### 問題: terraform.auto.tfvars が古い

**症状**: インベントリを更新したが反映されない

**解決策**:
```bash
# ファイルを削除して再生成
rm terraform/bootstrap/terraform.auto.tfvars
make generate-tfvars ENV=production
```

## 📝 新しい環境の追加

staging 環境などを追加する場合:

1. **インベントリファイルを作成**:
   ```bash
   cp ansible/inventory/inventory.ini ansible/inventory/inventory_staging.ini
   # IPアドレスを編集
   vim ansible/inventory/inventory_staging.ini
   ```

2. **Kustomize overlay を作成**:
   ```bash
   mkdir -p k8s/infra/metallb/overlays/staging
   cp k8s/infra/metallb/overlays/production/kustomization.yaml \
      k8s/infra/metallb/overlays/staging/
   # IPレンジを編集
   vim k8s/infra/metallb/overlays/staging/kustomization.yaml
   ```

3. **スクリプトを更新**:
   - `scripts/generate_tfvars.sh`: 環境検出ロジックに staging を追加
   - `scripts/patch_argocd_apps.sh`: staging を許可リストに追加
   - `terraform/bootstrap/variables.tf`: validation ルールに staging を追加

4. **Makefile を更新**:
   ```makefile
   .PHONY: ansible-setup-staging
   ansible-setup-staging: ## Staging環境でクラスターをセットアップ
   	$(MAKE) ENV=staging generate-tfvars
   	$(MAKE) ENV=staging patch-argocd-apps
   	cd ansible && ansible-playbook -i inventory/inventory_staging.ini site.yml
   ```

## 🎯 ベストプラクティス

### ✅ すべきこと

1. **インベントリファイルを真実の源とする**
   - すべての環境変数は Ansible インベントリで管理
   - 変更時は必ず `make generate-tfvars` を実行

2. **環境を明示的に指定**
   - デプロイ時は常に `ENV=<environment>` を指定
   - CI/CDでは環境変数で制御

3. **変更前に検証**
   ```bash
   make env-info ENV=production
   kustomize build k8s/infra/metallb/overlays/production
   ```

### ❌ すべきでないこと

1. **マニフェストに直接IPを書かない**
   - Kustomize overlay を使用

2. **terraform.auto.tfvars を手動編集しない**
   - 自動生成されるファイルなので上書きされます
   - 代わりにインベントリを編集

3. **複数環境を同時にデプロイしない**
   - 1つのクラスタ = 1つの環境

## 📚 参考資料

- [Kustomize Documentation](https://kustomize.io/)
- [ArgoCD Application Spec](https://argo-cd.readthedocs.io/en/stable/operator-manual/application.yaml)
- [MetalLB Configuration](https://metallb.universe.tf/configuration/)
- [Terraform Variables](https://www.terraform.io/language/values/variables)
