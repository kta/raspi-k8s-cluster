# K8s Directory - Phase 3: GitOps管理リソース

このディレクトリには、ArgoCDで管理されるKubernetesリソースのマニフェストが含まれています。

## ディレクトリ構造

```
k8s/
├── bootstrap/
│   └── root-app.yaml          # ArgoCD App of Apps
├── infra/
│   ├── cni/                   # ★ Flannel or Calico (CNIは必須)
│   ├── metallb/               # LoadBalancer
│   └── atlantis/              # Terraform Automation
└── apps/
    └── web-app/               # アプリケーション
```

## 使い方

```bash
# Root Appの適用
kubectl apply -f bootstrap/root-app.yaml

# 各コンポーネントはArgoCDが自動的にデプロイします
```
