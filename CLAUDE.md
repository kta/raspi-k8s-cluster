# CLAUDE.md

このファイルは、Claude Code (claude.ai/code) がこのリポジトリのコードを扱う際のガイダンスを提供します。

## プロジェクト概要

このプロジェクトは、4つのフェーズでRaspberry Piハードウェア上に高可用性Kubernetesクラスタを構築します：
- **フェーズ1**: OS設定とkubeadmによるクラスタブートストラップ（Ansible + シェルスクリプト）
- **フェーズ2**: ArgoCDによるインフラストラクチャブートストラップ（Terraform）
- **フェーズ3**: ArgoCDによるGitOps管理リソース（CNI、MetalLB、Atlantis）
- **フェーズ4**: アプリケーションデプロイ

## 主要コマンド

すべての操作はMakefileで管理されます。利用可能なコマンドを確認するには `make help` を実行してください。

### クラスタセットアップ
```bash
make setup-all                    # 全フェーズを実行 (ansible + terraform + argocd)
make ansible-setup                # フェーズ1: 実機でクラスタを構築
make ansible-setup-vagrant        # フェーズ1: Vagrant VM上でクラスタを構築
make fetch-kubeconfig             # プライマリノードからkubeconfigを取得
make terraform-apply              # フェーズ2: ArgoCDをインストール
make argocd-bootstrap             # フェーズ3: ルートArgoCDアプリケーションを適用
```

### Vagrantによる開発
```bash
make vagrant-up                   # VMを起動
make vagrant-destroy              # VMを破棄
make ansible-dev-debug            # フルリビルド: destroy + up + ansible + verify
```

### クラスタ管理
```bash
make status                       # ノード、Pod、サービスを表示
make ansible-verify               # 検証Playbookを実行
make ansible-reset                # クラスタをリセット (kubeadm reset)
make ansible-upgrade              # ローリングアップグレード（一度に1バージョンのみ）
```

## アーキテクチャ

### 設計思想
Ansibleがオーケストレーション（実行順序）を担当し、シェルスクリプトが実際のビルドロジックを含みます。このアプローチには以下の利点があります：
- Ansibleモジュールのバージョン互換性の問題を回避
- 独立したスクリプトで操作を可視化
- `ansible/scripts/` 内のスクリプトはAnsible無しでも再利用可能

### コアコンポーネント

**ansible/scripts/** - すべてのクラスタビルドロジックを含む：
- `common_setup.sh` - OS設定（swap、cgroups、モジュール）、containerd、kubeadmツール、Keepalived VIP、HAProxyロードバランサー
- `primary_init.sh` - `kubeadm init` の実行、Flannel CNIのインストール、参加トークンの生成
- `secondary_init.sh` - セカンダリコントロールプレーンノード用の `kubeadm join` を実行
- `cni_setup.sh` - CNI設定

**ansible/site.yml** - メインPlaybookで以下を実行：
1. 全ノードでノード固有のパラメータ（VIP、priority、state）を用いて common_setup.sh を実行
2. プライマリマスターで primary_init.sh を実行し、join コマンドを取得
3. `add_host` を使用して join コマンドを TOKEN_HOLDER で共有
4. セカンダリマスターで join コマンドを使って secondary_init.sh を実行

**インベントリ変数**（`ansible/inventory/*.ini` 内）：
- `k8s_version` - Kubernetesバージョン（例：1.35）
- `vip` - Keepalived用仮想IP
- `interface` - ネットワークインターフェース（eth0、end0など）
- `haproxy_port` - HAProxyポート（6443との競合を避けるため8443）
- `node_ips` - 全ノードIPのカンマ区切りリスト
- `priority`/`state` - Keepalivedの優先度と初期状態（MASTER/BACKUP）

### 高可用性セットアップ
- 3ノードのコントロールプレーン（すべてマスター、taint除去によりPodの配置を許可）
- Keepalivedが仮想IPフェイルオーバーを提供
- HAProxyがAPIサーバートラフィックをノード間で負荷分散
- コントロールプレーンエンドポイントは VIP:HAProxy_port を使用

## リンティング

シェルスクリプトは shellcheck を通過する必要があります。Ansible Playbookは ansible-lint を通過する必要があります。
