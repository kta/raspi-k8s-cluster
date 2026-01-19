# k8s/ ディレクトリ構造

## 概要

この構造は**環境ごとのGitファイル変更を排除**した最高のベストプラクティスです。

## ディレクトリ構成

```
k8s/
├── bootstrap/              # エントリーポイント（環境別）
│   ├── production.yaml     # 本番環境用
│   └── vagrant.yaml        # 開発環境用
│
├── envs/                   # 環境別のApplication定義
│   ├── production/         # 本番環境のApp定義
│   │   ├── cni.yaml
│   │   └── metallb.yaml
│   └── vagrant/            # 開発環境のApp定義
│       ├── cni.yaml
│       └── metallb.yaml
│
├── infra/                  # 実際のKubernetesリソース
│   ├── cni/
│   ├── metallb/
│   │   ├── metallb.yaml    # MetalLB本体
│   │   ├── base/           # Kustomize base
│   │   └── overlays/       # 環境別設定
│   └── ...
│
└── apps/                   # アプリケーション（Phase 4）
```

## メリット

✅ **Gitファイル変更不要** - 環境切り替えでコミット不要  
✅ **明確な分離** - 環境ごとのApplicationが一目瞭然  
✅ **DRY原則** - リソース定義は1箇所のみ  
✅ **保守性向上** - 環境追加が容易  
✅ **ベストプラクティス** - GitOps標準パターンに準拠

## 使い方

```bash
# 開発環境
make argocd-bootstrap ENV=vagrant

# 本番環境
make argocd-bootstrap ENV=production
```
