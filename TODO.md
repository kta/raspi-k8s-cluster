# TODO: Proxmox HA Kubernetes Cluster 構築タスク

## フェーズ1: プロジェクト基盤セットアップ

- [ ] **1.1 リポジトリ初期化**
  - [ ] `.gitignore` 作成 (Terraform state, secrets, .env など)
  - [ ] `.terraform-version` 作成 (Terraform バージョン固定)
  - [ ] `.tflint.hcl` 作成 (Proxmox プロバイダー用リンティング設定)
  - [ ] `README.md` 作成 (プロジェクト概要、セットアップ手順)

- [ ] **1.2 ディレクトリ構造作成**
  - [ ] `terraform/` ディレクトリ作成
  - [ ] `templates/` ディレクトリ作成
  - [ ] `docs/` ディレクトリ作成

## フェーズ2: Terraform 基本構成

- [ ] **2.1 Terraform プロバイダー設定**
  - [ ] `terraform/providers.tf` 作成
    - [ ] `bpg/proxmox` プロバイダー設定
    - [ ] `hashicorp/helm` プロバイダー設定 (Kubernetes リソース用)
  - [ ] `terraform/versions.tf` 作成 (required_version, required_providers)

- [ ] **2.2 変数定義**
  - [ ] `terraform/variables.tf` 作成
    - [ ] Proxmox API 接続情報 (環境変数参照)
    - [ ] ネットワーク設定 (IP範囲, Gateway, DNS)
    - [ ] VM リソース設定 (CPU, Memory)
    - [ ] Ceph ストレージプール名
    - [ ] Kubernetes バージョン
    - [ ] GitHub ユーザー名 (SSH鍵取得用)
  - [ ] `terraform/terraform.tfvars.example` 作成 (サンプル設定)

- [ ] **2.3 出力定義**
  - [ ] `terraform/outputs.tf` 作成
    - [ ] VM IP アドレス一覧
    - [ ] kube-vip VIP アドレス
    - [ ] 次のステップの指示

## フェーズ3: Cloud-Init テンプレート作成

- [ ] **3.1 Cloud-Init テンプレート**
  - [ ] `templates/user-data.yaml.tftpl` 作成
    - [ ] タイムゾーン設定 (Asia/Tokyo)
    - [ ] スワップ無効化
    - [ ] カーネルモジュール設定 (overlay, br_netfilter)
    - [ ] sysctl 設定 (IP forwarding)
    - [ ] containerd インストールと設定
    - [ ] Kubernetes v1.35 APT リポジトリ設定
    - [ ] kubelet, kubeadm, kubectl インストール
    - [ ] SSH 鍵取得 (GitHub API)

## フェーズ4: Terraform VM モジュール作成

- [ ] **4.1 Debian イメージダウンロード**
  - [ ] `terraform/main.tf` に `proxmox_virtual_environment_download_file` リソース追加
    - [ ] Debian 13 Trixie ARM64 Cloud Image URL 指定
    - [ ] Proxmox ストレージに保存

- [ ] **4.2 VM モジュール作成**
  - [ ] `terraform/modules/vm/main.tf` 作成
    - [ ] `proxmox_virtual_environment_vm` リソース定義
    - [ ] Cloud-Init 設定注入
    - [ ] ネットワーク設定
    - [ ] ディスク設定 (Ceph ストレージ使用)
  - [ ] `terraform/modules/vm/variables.tf` 作成
  - [ ] `terraform/modules/vm/outputs.tf` 作成

- [ ] **4.3 Control Plane VM デプロイ**
  - [ ] `terraform/main.tf` で Control Plane VM モジュール呼び出し
    - [ ] `pve-vm-cp-1` (192.168.100.201) on pi-node-1
    - [ ] `pve-vm-cp-2` (192.168.100.202) on pi-node-2
    - [ ] `pve-vm-cp-3` (192.168.100.203) on pi-node-3

- [ ] **4.4 Worker VM デプロイ**
  - [ ] `terraform/main.tf` で Worker VM モジュール呼び出し
    - [ ] `pve-vm-wk-1` (192.168.100.211) on pi-node-1
    - [ ] `pve-vm-wk-2` (192.168.100.212) on pi-node-2
    - [ ] `pve-vm-wk-3` (192.168.100.213) on pi-node-3

## フェーズ5: Kubernetes ブートストラップ (Terraform 経由)

- [ ] **5.1 kube-vip マニフェスト準備**
  - [ ] `templates/kube-vip-manifest.yaml.tftpl` 作成
    - [ ] VIP 192.168.100.200 設定
    - [ ] ARP モード設定
    - [ ] Control Plane 初期化時に配置

- [ ] **5.2 Kubernetes 初期化スクリプト**
  - [ ] `terraform/modules/kubernetes/` モジュール作成
    - [ ] `null_resource` + `remote-exec` で kubeadm init 実行
    - [ ] kube-vip マニフェスト配置
    - [ ] Join token 生成
    - [ ] kubeconfig 取得

- [ ] **5.3 Control Plane Join**
  - [ ] `null_resource` で残り2台の Control Plane を kubeadm join

- [ ] **5.4 Worker Node Join**
  - [ ] `null_resource` で 3台の Worker を kubeadm join

## フェーズ6: CNI と ArgoCD インストール (Helm Provider)

- [ ] **6.1 CNI インストール**
  - [ ] `terraform/modules/kubernetes/` に Helm リソース追加
    - [ ] Flannel または Cilium の Helm Chart デプロイ
    - [ ] CNI 適用完了まで待機

- [ ] **6.2 ArgoCD インストール**
  - [ ] `terraform/modules/argocd/` モジュール作成
    - [ ] ArgoCD Helm Chart デプロイ
    - [ ] Namespace: `argocd`
    - [ ] 初期パスワード取得と出力

## フェーズ7: ドキュメント整備

- [ ] **7.1 セットアップガイド**
  - [ ] `docs/setup.md` 作成
    - [ ] 前提条件 (Proxmox + Ceph 構築済み)
    - [ ] 環境変数設定方法
    - [ ] Terraform 実行手順
    - [ ] クラスター動作確認方法

- [ ] **7.2 トラブルシューティング**
  - [ ] `docs/troubleshooting.md` 作成
    - [ ] VM が起動しない場合
    - [ ] Kubernetes Join に失敗する場合
    - [ ] ネットワーク疎通確認方法
    - [ ] Ceph ストレージエラー対処

- [ ] **7.3 メンテナンスガイド**
  - [ ] `docs/maintenance.md` 作成
    - [ ] VM の追加/削除方法
    - [ ] Kubernetes バージョンアップグレード
    - [ ] Ceph 容量拡張

## フェーズ8: Atlantis セットアップ (オプション)

- [ ] **8.1 Atlantis 設定ファイル**
  - [ ] `atlantis.yaml` 作成
    - [ ] Terraform ワークフロー定義
    - [ ] `terraform plan` / `apply` 設定
  - [ ] `.github/workflows/atlantis.yaml` 作成 (外部サーバー起動用)

- [ ] **8.2 Atlantis デプロイ**
  - [ ] フェーズ1: Docker Compose で外部起動
  - [ ] フェーズ2: クラスター構築後、K8s にセルフホスト

## フェーズ9: ArgoCD App of Apps パターン構成

- [ ] **9.1 ArgoCD アプリケーション管理リポジトリ**
  - [ ] 別リポジトリまたは `/argocd-apps` ディレクトリ作成
  - [ ] `app-of-apps.yaml` 作成 (ルートアプリケーション)

- [ ] **9.2 サンプルアプリケーション登録**
  - [ ] Prometheus / Grafana
  - [ ] Cert-Manager
  - [ ] サンプルビジネスアプリ

## フェーズ10: テストと検証

- [ ] **10.1 インフラ検証**
  - [ ] 全 VM が正常起動
  - [ ] Ceph ストレージが正常動作
  - [ ] ネットワーク疎通確認

- [ ] **10.2 Kubernetes 検証**
  - [ ] `kubectl get nodes` で全ノード Ready
  - [ ] `kubectl get pods -A` で全 Pod Running
  - [ ] kube-vip VIP にアクセス可能

- [ ] **10.3 高可用性検証**
  - [ ] 物理ノード1台停止時の動作確認
  - [ ] Control Plane 定足数維持確認
  - [ ] Ceph データ保持確認

- [ ] **10.4 ArgoCD 検証**
  - [ ] ArgoCD UI アクセス確認
  - [ ] サンプルアプリのデプロイ確認
  - [ ] Git 同期の動作確認

## 完了条件

- [ ] すべてのフェーズが完了
- [ ] ドキュメントが整備され、第三者が再現可能
- [ ] 高可用性が検証済み
- [ ] ArgoCD で継続的なアプリケーション管理が可能

---

## 注意事項

- 各フェーズは順番に実行すること
- Terraform の変更は必ず `tflint` で検証すること
- 機密情報 (API トークン, パスワード) は Git にコミットしないこと
- フェーズ完了ごとに動作確認を行うこと
