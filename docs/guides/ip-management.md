# 環境別IP管理ガイド

このガイドでは、実機（production）とVagrant環境で異なるIPアドレスを自動的に使い分ける仕組みを説明します。

## 🎯 概要

プロジェクトは2つの環境で異なるIPレンジを自動管理します：

| 環境 | ノードIP | VIP | MetalLB | Ingress IP |
|------|---------|-----|---------|-----------|
| **production** | 192.168.1.101-103 | 192.168.1.100 | 192.168.1.200-220 | 192.168.1.200 |
| **vagrant** | 192.168.56.101-103 | 192.168.56.100 | 192.168.56.200-220 | 192.168.56.200 |

## 🏗️ アーキテクチャ（新構造 2026-01）

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
│ 4. ArgoCD ApplicationSet            │
│    bootstrap/root.yaml              │
│    → bootstrap/values/*.yaml を検出 │
│    → 環境別Applicationを生成        │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ 5. Kustomize Overlays               │
│    apps/overlays/{env}              │
│    infra/*/overlays/{env}           │
│    → 環境別パラメータをパッチ       │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ 6. Kubernetes Resources             │
│    環境別IP設定が自動適用           │
└─────────────────────────────────────┘
```

### 重要な変更点（2026-01リファクタリング）

**旧構造の問題点:**
- ❌ `patch_argocd_apps.sh` による手動パッチング
- ❌ 環境ごとに重複したApplication定義
- ❌ `01-`, `02-` などの番号プレフィックス

**新構造の改善:**
- ✅ ApplicationSetによる環境自動検出
- ✅ Kustomize base/overlaysで重複排除
- ✅ sync-waveアノテーションで依存管理
- ✅ 完全自動化（手動パッチング不要）

## 📝 設定ファイル

### 1. Ansible Inventory（真実の源）

#### Production: `ansible/inventory/inventory.ini`

```ini
[all_masters]
pi-node1 ansible_host=192.168.1.101 priority=101 state=MASTER
pi-node2 ansible_host=192.168.1.102 priority=100 state=BACKUP
pi-node3 ansible_host=192.168.1.103 priority=100 state=BACKUP

[all:vars]
ansible_user=pi
vip=192.168.1.100
interface=eth0
k8s_version=1.35
haproxy_port=8443
node_ips=192.168.1.101,192.168.1.102,192.168.1.103
metallb_ip_range=192.168.1.200-192.168.1.220
ingress_ip=192.168.1.200
environment=production
```

#### Vagrant: `ansible/inventory/inventory_vagrant.ini`

```ini
[all_masters]
primary ansible_host=192.168.56.101 priority=101 state=MASTER
secondary1 ansible_host=192.168.56.102 priority=100 state=BACKUP
secondary2 ansible_host=192.168.56.103 priority=100 state=BACKUP

[all:vars]
ansible_user=vagrant
vip=192.168.56.100
interface=eth1
k8s_version=1.35
haproxy_port=8443
node_ips=192.168.56.101,192.168.56.102,192.168.56.103
metallb_ip_range=192.168.56.200-192.168.56.220
ingress_ip=192.168.56.200
environment=vagrant
```

### 2. ApplicationSet環境パラメータ

#### Production: `k8s/bootstrap/values/production.yaml`

```yaml
environment: production
repoURL: https://github.com/kta/raspi-k8s-cluster.git
targetRevision: main

metallb:
  ipRange: 192.168.1.200-192.168.1.220
  
ingress:
  ip: 192.168.1.200
  domain: raspi.local

argocd:
  hostname: argocd.raspi.local

certManager:
  email: admin@raspi.local
  acmeServer: https://acme-v02.api.letsencrypt.org/directory
```

#### Vagrant: `k8s/bootstrap/values/vagrant.yaml`

```yaml
environment: vagrant
repoURL: https://github.com/kta/raspi-k8s-cluster.git
targetRevision: main

metallb:
  ipRange: 192.168.56.200-192.168.56.220
  
ingress:
  ip: 192.168.56.200
  domain: raspi.local

argocd:
  hostname: argocd.raspi.local

certManager:
  email: admin@raspi.local
  acmeServer: https://acme-staging-v02.api.letsencrypt.org/directory  # Staging
```

### 3. Kustomize Overlays

#### MetalLB Production: `k8s/infra/metallb/overlays/production/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: metallb-system

resources:
  - ../../base

patches:
  - target:
      kind: IPAddressPool
      name: default
    patch: |-
      - op: replace
        path: /spec/addresses/0
        value: "192.168.1.200-192.168.1.220"
```

#### MetalLB Vagrant: `k8s/infra/metallb/overlays/vagrant/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: metallb-system

resources:
  - ../../base

patches:
  - target:
      kind: IPAddressPool
      name: default
    patch: |-
      - op: replace
        path: /spec/addresses/0
        value: "192.168.56.200-192.168.56.220"
```

## 🔄 IP変更手順

### Production環境のIP変更

```bash
# 1. Ansibleインベントリを編集
vim ansible/inventory/inventory.ini
# metallb_ip_range, ingress_ip, vipなどを変更

# 2. ApplicationSet環境パラメータを編集（オプション）
vim k8s/bootstrap/values/production.yaml
# metallb.ipRange, ingress.ipを変更

# 3. Kustomize overlayを編集
vim k8s/infra/metallb/overlays/production/kustomization.yaml
# IPアドレスレンジを変更

# 4. Terraform変数を再生成
make generate-tfvars ENV=production

# 5. 変更をコミット
git add .
git commit -m "Update production IP ranges"
git push

# 6. ArgoCDが自動的に同期（auto-syncが有効な場合）
# 手動同期の場合:
kubectl apply -f k8s/bootstrap/root.yaml
argocd app sync -l app.kubernetes.io/instance=infra-production
```

### Vagrant環境のIP変更

```bash
# 1. Ansibleインベントリを編集
vim ansible/inventory/inventory_vagrant.ini

# 2. ApplicationSet環境パラメータを編集
vim k8s/bootstrap/values/vagrant.yaml

# 3. Kustomize overlayを編集
vim k8s/infra/metallb/overlays/vagrant/kustomization.yaml

# 4. Terraform変数を再生成
make generate-tfvars ENV=vagrant

# 5. 変更をコミット & push
git add . && git commit -m "Update vagrant IP ranges" && git push

# 6. ArgoCD同期
kubectl apply -f k8s/bootstrap/root.yaml
argocd app sync -l app.kubernetes.io/instance=infra-vagrant
```

## 🚀 新規環境の追加

### 1. Ansibleインベントリ作成

```bash
cp ansible/inventory/inventory.ini ansible/inventory/inventory_staging.ini
vim ansible/inventory/inventory_staging.ini
# 新しいIPレンジに変更
# environment=staging
```

### 2. ApplicationSet環境パラメータ作成

```bash
cat > k8s/bootstrap/values/staging.yaml << 'YAML'
environment: staging
repoURL: https://github.com/kta/raspi-k8s-cluster.git
targetRevision: main

metallb:
  ipRange: 192.168.10.200-192.168.10.220
  
ingress:
  ip: 192.168.10.200
  domain: raspi.local

argocd:
  hostname: argocd.raspi.local

certManager:
  email: admin@raspi.local
  acmeServer: https://acme-staging-v02.api.letsencrypt.org/directory
YAML
```

### 3. Kustomize Overlays作成

```bash
# MetalLB
mkdir -p k8s/infra/metallb/overlays/staging
cat > k8s/infra/metallb/overlays/staging/kustomization.yaml << 'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: metallb-system

resources:
  - ../../base

patches:
  - target:
      kind: IPAddressPool
      name: default
    patch: |-
      - op: replace
        path: /spec/addresses/0
        value: "192.168.10.200-192.168.10.220"
YAML

# Cert-Manager
mkdir -p k8s/infra/cert-manager/overlays/staging
cat > k8s/infra/cert-manager/overlays/staging/kustomization.yaml << 'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: cert-manager

resources:
  - ../../base

patches:
  - target:
      kind: ClusterIssuer
      name: letsencrypt
    patch: |-
      - op: replace
        path: /spec/acme/server
        value: "https://acme-staging-v02.api.letsencrypt.org/directory"
YAML

# ArgoCD Ingress
mkdir -p k8s/infra/argocd/overlays/staging
cp k8s/infra/argocd/overlays/production/kustomization.yaml \
   k8s/infra/argocd/overlays/staging/kustomization.yaml

# Atlantis Ingress
mkdir -p k8s/infra/atlantis/overlays/staging
cp k8s/infra/atlantis/overlays/production/kustomization.yaml \
   k8s/infra/atlantis/overlays/staging/kustomization.yaml
```

### 4. Application Overlays作成

```bash
mkdir -p k8s/apps/overlays/staging
cat > k8s/apps/overlays/staging/kustomization.yaml << 'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: argocd

resources:
  - ../../base

patches:
  - target:
      kind: Application
      name: metallb-config
    patch: |-
      - op: replace
        path: /spec/source/path
        value: k8s/infra/metallb/overlays/staging

  - target:
      kind: Application
      name: cert-manager-resources
    patch: |-
      - op: replace
        path: /spec/source/path
        value: k8s/infra/cert-manager/overlays/staging

  - target:
      kind: Application
      name: traefik
    patch: |-
      - op: replace
        path: /spec/source/helm/valuesObject/service/annotations/metallb.universe.tf~1loadBalancerIPs
        value: "192.168.10.200"

  - target:
      kind: Application
      name: argocd-ingress
    patch: |-
      - op: replace
        path: /spec/source/path
        value: k8s/infra/argocd/overlays/staging

  - target:
      kind: Application
      name: atlantis-ingress
    patch: |-
      - op: replace
        path: /spec/source/path
        value: k8s/infra/atlantis/overlays/staging
YAML
```

### 5. デプロイ

```bash
# Terraform変数生成
make generate-tfvars ENV=staging

# コミット & push
git add .
git commit -m "Add staging environment"
git push

# ApplicationSetが自動的に新環境を検出してデプロイ
kubectl get appset -n argocd infra-root -o yaml
kubectl get app -n argocd | grep infra-staging
```

## 🔍 環境別デプロイ確認

```bash
# ApplicationSetの状態確認
kubectl get appset -n argocd

# 生成されたApplications確認
kubectl get app -n argocd | grep infra-

# 特定環境のApplication詳細
kubectl get app -n argocd infra-production -o yaml
kubectl get app -n argocd infra-vagrant -o yaml

# MetalLB IP Pool確認
kubectl get ipaddresspool -n metallb-system -o yaml

# Traefik LoadBalancer IP確認
kubectl get svc -n traefik traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

## 🏆 ベストプラクティス

1. **単一真実の源**: すべてのIPはAnsibleインベントリで管理
2. **自動同期**: ApplicationSetのauto-sync機能を有効化
3. **環境パリティ**: production/vagrant/stagingで同じ構造を維持
4. **変更履歴**: Git commitメッセージにIP変更理由を記載
5. **検証**: 変更後は必ず `kubectl get ipaddresspool` で確認

## 🆘 トラブルシューティング

### ApplicationSetが環境を検出しない

```bash
# ApplicationSet設定確認
kubectl get appset -n argocd infra-root -o yaml

# generator設定を確認
# files pathが "k8s/bootstrap/values/*.yaml" になっているか確認

# values/*.yaml ファイルが正しいか確認
ls -la k8s/bootstrap/values/
cat k8s/bootstrap/values/production.yaml
```

### IP変更が反映されない

```bash
# 1. Kustomize overlayを確認
kubectl kustomize k8s/infra/metallb/overlays/production

# 2. Application sync状態確認
kubectl get app -n argocd -o json | jq -r '.items[] | "\(.metadata.name): \(.status.sync.status)"'

# 3. 手動sync
argocd app sync metallb-config

# 4. IPAddressPool確認
kubectl get ipaddresspool -n metallb-system -o yaml
```

### 環境別でデプロイされない

```bash
# Applicationのpathがcorrectか確認
kubectl get app -n argocd infra-production -o yaml | grep path

# 期待値: k8s/apps/overlays/production
# 実際の値が違う場合、ApplicationSet templateを確認
```

## 📚 関連ドキュメント

- [クイックスタート](./quickstart.md) - セットアップ手順
- [サービスアクセス](./service-access.md) - ArgoCD/Atlantis アクセス
- [トラブルシューティング](./troubleshooting.md) - 問題解決
- [k8s/README.md](../../k8s/README.md) - k8s構造詳細
- [k8s/MIGRATION.md](../../k8s/MIGRATION.md) - 旧構造からの移行
