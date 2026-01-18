# 環境別IP管理 クイックスタート

## 🎯 やりたいこと

実機（production）とVagrant環境で**異なるIPアドレスレンジを自動的に使い分ける**

## ⚡ 使い方

### 実機環境

```bash
# 1. インベントリファイルでIPを定義 (既に設定済み)
cat ansible/inventory/inventory.ini
# vip=192.168.1.100
# metallb_ip_range=192.168.1.200-192.168.1.220
# ingress_ip=192.168.1.200

# 2. セットアップ（自動で変数生成とパッチ適用）
make ansible-setup ENV=production
make fetch-kubeconfig
make terraform-apply
make argocd-bootstrap
```

### Vagrant環境

```bash
# すべて自動化！
make ansible-setup-vagrant
make fetch-kubeconfig-vagrant
make terraform-apply ENV=vagrant
make argocd-bootstrap
```

## 🔍 何が起こっているか

```
Ansible Inventory (定義)
    ↓ (scripts/generate_tfvars.sh)
Terraform Variables (自動生成)
    ↓ (terraform apply)
ConfigMap in Kubernetes
    ↓ (scripts/patch_argocd_apps.sh)
ArgoCD Applications (環境別overlay)
    ↓
MetalLB with correct IP range
```

## 📝 設定変更したい時

```bash
# 1. インベントリを編集
vim ansible/inventory/inventory.ini

# 2. Terraform変数を再生成
make generate-tfvars ENV=production

# 3. ArgoCD Applicationを再適用
make patch-argocd-apps ENV=production

# 4. Terraformを再実行
cd terraform/bootstrap && terraform apply

# 5. ArgoCDを同期
kubectl apply -f k8s/bootstrap/root-app.yaml
```

詳細は [environment_ip_management.md](./environment_ip_management.md) を参照してください。
