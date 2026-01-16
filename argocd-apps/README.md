# ArgoCD App of Apps

このディレクトリには、ArgoCD の App of Apps パターンを使用したアプリケーション定義が含まれています。

## 構造

- `app-of-apps.yaml`: ルートアプリケーション（最初にデプロイ）
- `bootstrap/`: 子アプリケーションの定義
- `applications/`: 実際の Kubernetes マニフェスト

## 使用方法

詳細は [docs/argocd-setup.md](../docs/argocd-setup.md) を参照してください。

## クイックスタート

```bash
# App of Apps をデプロイ
kubectl apply -f argocd-apps/app-of-apps.yaml

# 状態確認
kubectl get applications -n argocd
```
