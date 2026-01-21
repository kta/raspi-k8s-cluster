# リファクタリング検証チェックリスト

## ✅ 完了した項目

### 1. ディレクトリ移行
- [x] `migrate_infrastructure.sh` 実行完了
- [x] 9個のコンポーネントを新しいレイヤー構造に移動
- [x] バックアップ作成: `.migration_backup_20260120_234339/`

### 2. Application定義パス更新
- [x] `update_application_paths.sh` 実行完了
- [x] 全Application定義のパスを新構造に更新:
  - `01-system/cni`
  - `02-network/metallb, traefik, cert-manager, cert-manager-resources`
  - `03-observability/monitoring-config, monitoring-nodeports, grafana`
  - `04-ops/atlantis, argocd`

### 3. Terraform設定更新
- [x] `terraform/modules/argocd/applicationset.tf` 更新
- [x] パス変更: `k8s/infrastructure/argocd-apps/overlays/{{.environment}}` 
  → `k8s/infrastructure/00-argocd-apps/argocd-apps/overlays/{{.environment}}`

### 4. Pure Helmアプリケーション
- [x] `k8s/applications/my-app/` 作成
- [x] Helm lint 成功
- [x] Template生成成功
- [x] SealedSecret統合

### 5. ドキュメント
- [x] `README.md` 更新
- [x] `k8s/REFACTORING_2026.md` 作成
- [x] `k8s/applications/my-app/README.md` 作成
- [x] Walkthrough作成

## 🔍 検証項目

### Terraform互換性
```bash
cd terraform/environments/vagrant
terraform init
terraform validate
terraform plan
```

**期待される結果:**
- ✅ 検証エラーなし
- ✅ ApplicationSetリソースが正しく生成される
- ✅ パス `k8s/infrastructure/00-argocd-apps/argocd-apps/overlays/vagrant` が正しい

### Application定義の整合性
```bash
# すべてのApplication定義を確認
find k8s/infrastructure/00-argocd-apps -name "*.yaml" -type f | \
  xargs grep "path: k8s/infrastructure/" | \
  grep -v "00-argocd-apps\|01-system\|02-network\|03-observability\|04-ops"
```

**期待される結果:**
- ✅ 古いパス構造が見つからない（出力なし）

### ディレクトリ構造の確認
```bash
tree -L 3 k8s/infrastructure/
```

**期待される結果:**
```
k8s/infrastructure/
├── 00-argocd-apps
│   └── argocd-apps
│       ├── base
│       └── overlays
├── 01-system
│   └── cni
│       ├── base
├── 02-network
│   ├── cert-manager
│   ├── cert-manager-resources
│   ├── metallb
│   └── traefik
├── 03-observability
│   ├── grafana
│   ├── monitoring-config
│   └── monitoring-nodeports
└── 04-ops
    ├── argocd
    └── atlantis
```

## ⚠️ 注意事項

### 破壊的変更
1. **ディレクトリ構造の変更**
   - 古い構造への参照はすべて無効
   - 外部ツールやスクリプトの更新が必要

2. **Terraform状態**
   - ApplicationSetリソースが再作成される可能性
   - `terraform plan`で変更内容を確認すること

3. **ArgoCD同期**
   - 初回デプロイ時、すべてのApplicationが再同期される
   - 一時的にOutOfSyncになる可能性

### ロールバック手順
問題が発生した場合：

```bash
# ディレクトリ構造のロールバック
cd /Users/spm/Documents/workspace/myspace/raspi-k8s-cluster/k8s
rm -rf infrastructure
mv .migration_backup_20260120_234339/infrastructure ./

# Gitでロールバック
git checkout HEAD -- terraform/modules/argocd/applicationset.tf
git checkout HEAD -- k8s/infrastructure/00-argocd-apps/
```

## 📋 次のステップ

### 1. Terraform検証
```bash
cd terraform/environments/vagrant
terraform init
terraform validate
terraform plan
```

### 2. 完全環境再構築
```bash
cd /Users/spm/Documents/workspace/myspace/raspi-k8s-cluster
make setup-all-vagrant
```

### 3. デプロイ確認
```bash
# ApplicationSet確認
kubectl get appset -n argocd

# Application確認
kubectl get app -n argocd

# すべてのリソース確認
kubectl get all -A
```

### 4. Git コミット
すべての検証が成功したら：
```bash
git add -A
git commit -m "refactor(k8s): migrate to layered infrastructure structure (00-04)

- Reorganize infrastructure into 5 layers (00-argocd-apps, 01-system, 02-network, 03-observability, 04-ops)
- Update all Application definition paths
- Update Terraform ApplicationSet configuration
- Add Pure Helm application sample (my-app)
- Update documentation"
git push
```

## 🎯 成功基準

- [ ] `terraform validate` 成功
- [ ] `make setup-all-vagrant` 成功
- [ ] すべてのApplicationが `Synced` 状態
- [ ] すべてのPodが `Running` 状態
- [ ] ArgoCD UIで全コンポーネントが正常表示
