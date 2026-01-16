# Copilot Instructions: Proxmox HA Kubernetes Cluster (GitOps Edition)

## プロジェクト概要

3台の Raspberry Pi 5 上に高可用性 Kubernetes クラスターを構築するプロジェクト:
- **物理層**: Raspberry Pi 5 (8GB) × 3台
- **仮想化**: Proxmox VE (Pimox)
- **ストレージ**: Ceph 分散ストレージ
- **コンテナ基盤**: Kubernetes v1.35 (kubeadm)
- **IaC**: Terraform + Cloud-Init
- **GitOps**: ArgoCD によるアプリケーション管理
- **自動化**: Atlantis による PR 駆動の Terraform ワークフロー

## アーキテクチャ

### 物理トポロジー
- **pi-node-1** (192.168.100.101): Control Plane VM + Worker VM
- **pi-node-2** (192.168.100.102): Control Plane VM + Worker VM  
- **pi-node-3** (192.168.100.103): Control Plane VM + Worker VM

### VM 配置 (合計6台)
- **Control Planes**: `pve-vm-cp-1` (192.168.100.201), `pve-vm-cp-2` (.202), `pve-vm-cp-3` (.203)
- **Workers**: `pve-vm-wk-1` (192.168.100.211), `pve-vm-wk-2` (.212), `pve-vm-wk-3` (.213)
- **仮想IP (kube-vip)**: 192.168.100.200

### VM スペック
- **OS**: Debian 13 "Trixie" (Testing) ARM64
- **リソース**: 各VM 2 vCPU, 2GB RAM
- **ユーザー**: `debian`
- **SSH**: GitHub 公開鍵 (https://github.com/kta.keys)

## ネットワーク構成

- **ゲートウェイ**: 192.168.100.1
- **DNS**: 192.168.100.1
- **ドメインなし** - `/etc/hosts` と `cluster.local` を使用
- **接続**: 有線LANのみ (1Gbps以上)

## ストレージ構成

- **Ceph プール**: `ceph-vm` (事前に手動構築済み)
- **レプリケーション**: size=3, min_size=2
- **OSD**: 各物理ノードに USB SSD 1台 (合計3台)
- **MON/MGR**: 全3物理ノード

## Infrastructure as Code

### Terraform 構成

**プロバイダー**: `bpg/proxmox`

**環境変数** (コミット禁止):
```bash
PM_API_URL=https://192.168.100.101:8006/
PM_API_TOKEN_ID=user@pam!token_id
PM_API_TOKEN_SECRET=uuid-secret-key
```

**バージョン管理**:
- `.terraform-version` ファイルで `tfenv` を使用
- `.tflint.hcl` で `tflint` によるリンティング

**責務**:
1. `proxmox_virtual_environment_download_file` で Debian Trixie ARM64 イメージをダウンロード
2. 6台のVMを物理ノードに分散配置
3. Cloud-Init 設定を注入
4. kubeadm で Kubernetes クラスターをブートストラップ
5. Helm プロバイダーでシステムレベルアプリをインストール:
   - CNI (Cilium または Flannel)
   - ArgoCD (初期インストールのみ)

### Cloud-Init 構成

**テンプレート配置**: `./templates/user-data.yaml.tftpl`

**責務**:
- スワップ無効化
- タイムゾーン設定
- カーネルモジュール読み込み (overlay, br_netfilter)
- IP フォワーディング有効化
- パッケージインストール: kubelet, kubeadm, kubectl, containerd
- Kubernetes v1.35 APT リポジトリ設定
- containerd の SystemdCgroup 設定
- GitHub から SSH 鍵を取得

## Kubernetes 構成

### コアコンポーネント
- **バージョン**: v1.35
- **APT Repo**: `pkgs.k8s.io/core:/stable:/v1.35/deb/`
- **ランタイム**: containerd (SystemdCgroup 有効)
- **CNI**: Flannel または Cilium (Terraform Helm プロバイダーでインストール)
- **ロードバランサー**: kube-vip (ARPモード) on VIP 192.168.100.200

### ブートストラップ手順
1. kube-vip で最初の Control Plane を初期化
2. 残りの Control Plane をジョイン
3. Worker ノードをジョイン
4. Helm で CNI を適用
5. Helm で ArgoCD をインストール

## GitOps ワークフロー

### Atlantis (Terraform 自動化)
- **フェーズ1**: クラスター構築のため外部で実行
- **フェーズ2**: K8s 上のセルフホスト Pod へ移行
- **機能**: PR 駆動の `terraform plan` / `apply`

### ArgoCD (アプリケーション管理)
- **パターン**: App of Apps
- **スコープ**: インフラストラクチャ ブートストラップ以外のすべてのアプリケーション
- **管理対象アプリ**:
  - ビジネスアプリケーション
  - 監視 (Prometheus, Grafana)
  - Cert-Manager
  - その他のアドオン

## プロジェクトディレクトリ構成

```
.
├── README.md
├── .github/
│   └── copilot-instructions.md
├── .terraform-version          # tfenv バージョン固定
├── .tflint.hcl                 # Terraform リンティング設定
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── providers.tf
│   └── modules/
│       ├── vm/
│       ├── kubernetes/
│       └── argocd/
├── templates/
│   └── user-data.yaml.tftpl    # Cloud-Init テンプレート
└── docs/
    ├── setup.md
    └── troubleshooting.md
```

## 非機能要件

### 可用性
- 物理ノード1台の障害に耐える
- Ceph は 2/3 ノードでデータ保持
- K8s コントロールプレーンは 2/3 ノードで定足数維持

### リソース制約
- **メモリ**: 厳しい (各ノード VM用 4GB + Ceph/OS用 3GB)
- **ストレージ**: USB接続 (高I/Oワークロードには不向き)
- **Pod制限**: OOM防止のため必ずメモリ制限を設定

### セキュリティ
- Git にシークレットを含めない
- 認証情報は環境変数で管理
- SSH鍵認証のみ使用

## 開発ワークフロー

1. **コード変更**: Terraform/テンプレートを変更
2. **リント**: `tflint` で検証
3. **PR作成**: Pull Request を作成
4. **Atlantis**: 自動で `terraform plan` 実行
5. **レビュー**: plan 出力を確認
6. **マージ**: Atlantis が `terraform apply` を実行
7. **ArgoCD**: Git を監視してアプリケーション変更を適用

## 重要原則

- **IaC ファースト**: すべてのインフラ変更は Terraform 経由
- **シェルスクリプト禁止**: Terraform + Cloud-Init runcmd を使用
- **関心の分離**: 
  - Terraform = インフラストラクチャ ブートストラップ
  - ArgoCD = アプリケーション管理
- **イミュータブルインフラ**: 変更ではなく再作成
- **GitOps**: Git を唯一の信頼できる情報源とする

## よくあるタスク

### Terraform を変更する場合:
- Terraform バージョン変更時は `.terraform-version` を更新
- コミット前に `tflint` を実行
- 別ブランチでテスト
- Atlantis による PR 駆動ワークフローを使用

### Kubernetes アプリケーションを追加する場合:
- Terraform には追加しない
- ArgoCD の App of Apps パターンに追加
- ArgoCD に Git から同期させる

### デバッグ時:
- Proxmox で VM 状態を確認
- Ceph ヘルスチェック: `ceph -s`
- K8s チェック: `kubectl get nodes`, `kubectl get pods -A`
- ArgoCD 同期状態を確認

## 制約と制限事項

- **Wi-Fi不可**: 安定性のため有線LANのみ
- **最低4GB RAM**: Ceph + VM 用に必要
- **USB ストレージ**: I/O パフォーマンス制限あり
- **ARM64のみ**: すべてのイメージは ARM64 互換である必要がある
- **Proxmox事前構築**: Proxmox + Ceph が準備済みであることが前提
- **Ceph手動構築**: Ceph クラスターのセットアップは自動化されていない

## 参考資料

- Kubernetes v1.35: https://kubernetes.io/docs/
- Proxmox Provider: https://registry.terraform.io/providers/bpg/proxmox/
- ArgoCD: https://argo-cd.readthedocs.io/
- Debian Cloud Images: https://cloud.debian.org/images/cloud/
