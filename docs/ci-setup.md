# CI/CD セットアップガイド

このドキュメントでは、GitHub Actions と Ansible Molecule を使用した CI/CD パイプラインについて説明します。

## 概要

このプロジェクトでは、以下のツールを使用して自動テストを実行します：

- **Molecule**: Ansible ロールとプレイブックのテストフレームワーク
- **Docker**: テスト環境としてコンテナを使用（VirtualBox の代替）
- **GitHub Actions**: CI/CD パイプライン
- **ShellCheck**: シェルスクリプトの静的解析
- **ansible-lint**: Ansible プレイブックのリンティング
- **yamllint**: YAML ファイルのリンティング

## ディレクトリ構造

```
raspi-k8s-cluster/
├── .github/
│   └── workflows/
│       └── ci.yml                    # GitHub Actions ワークフロー定義
├── ansible/
│   ├── molecule/
│   │   └── default/
│   │       ├── molecule.yml          # Molecule 設定
│   │       ├── prepare.yml           # テスト前の準備
│   │       ├── converge.yml          # テスト実行（簡略版 site.yml）
│   │       └── verify.yml            # テスト検証
│   ├── scripts/                      # シェルスクリプト
│   ├── site.yml                      # メインプレイブック
│   └── .ansible-lint                 # ansible-lint 設定
├── .yamllint                         # yamllint 設定
└── requirements.txt                  # Python 依存関係
```

## テスト戦略

### 1. リンティング（Lint）

#### ShellCheck
すべてのシェルスクリプト（`ansible/scripts/*.sh`）に対して ShellCheck を実行し、構文エラーや潜在的な問題を検出します。

```bash
find ansible/scripts -name "*.sh" -type f -exec shellcheck {} +
```

#### ansible-lint
Ansible プレイブックのベストプラクティス違反をチェックします。

```bash
cd ansible
ansible-lint site.yml verify.yml reset.yml upgrade.yml
```

#### yamllint
YAML ファイルのフォーマットと構文をチェックします。

```bash
yamllint -c .yamllint ansible/
```

### 2. Molecule テスト

Molecule は Docker コンテナ内で Ansible プレイブックを実行し、結果を検証します。

#### テストシナリオ

**molecule.yml** で以下を定義：
- 3つの Docker コンテナ（primary-master, secondary-master-1, secondary-master-2）
- systemd 対応のイメージ（`geerlingguy/docker-ubuntu2204-ansible`）
- ネットワーク設定とグループ変数

**テストフロー**:
1. **prepare.yml**: コンテナの初期設定
2. **converge.yml**: Ansible プレイブックの実行（簡略版）
3. **verify.yml**: 結果の検証

#### 検証項目

- ✅ スクリプトが正しくコピーされているか
- ✅ スクリプトに実行権限があるか
- ✅ 必要なパッケージ（containerd など）がインストールされているか
- ✅ ノードのロール（primary/secondary）が正しく設定されているか
- ✅ ネットワークインターフェースが存在するか

## ローカルでのテスト実行

### 前提条件

- Python 3.11+
- Docker
- pip

### セットアップ

```bash
# Python 依存関係のインストール
pip install -r requirements.txt

# または venv を使用
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### Molecule テストの実行

```bash
cd ansible

# すべてのテストシーケンスを実行
molecule test

# 個別のステップを実行
molecule create        # コンテナを作成
molecule converge      # プレイブックを実行
molecule verify        # 検証を実行
molecule destroy       # コンテナを削除

# ログイン（デバッグ用）
molecule login -h primary-master
```

### リンティングの実行

```bash
# ShellCheck
shellcheck ansible/scripts/*.sh

# ansible-lint
cd ansible
ansible-lint site.yml

# yamllint
yamllint -c .yamllint ansible/
```

## GitHub Actions ワークフロー

### トリガー

- `main` または `develop` ブランチへのプッシュ
- `main` または `develop` ブランチへのプルリクエスト
- 手動実行（workflow_dispatch）

### ジョブ

#### 1. Lint Job
- yamllint、ansible-lint、shellcheck を実行
- エラーがあっても継続（continue-on-error: true）

#### 2. Molecule Job
- Lint ジョブが成功した後に実行
- Docker コンテナ内で Molecule テストを実行
- 失敗時はログをアーティファクトとしてアップロード

#### 3. Test Summary Job
- すべてのジョブの結果をまとめて表示
- いずれかが失敗した場合はエラーを返す

## CI での制約と対応

### 制約

1. **VirtualBox 不可**: GitHub Actions ではネステッド仮想化が使用できない
2. **実環境との差異**: Docker コンテナは完全な VM ではない
3. **kubeadm の実行**: 実際のクラスタ初期化は行わない

### 対応策

1. **Docker + systemd**: systemd 対応のコンテナイメージを使用
2. **部分的なテスト**: スクリプトの配置と基本的な依存関係のインストールを検証
3. **ドライラン**: `converge.yml` では実際の kubeadm init/join は実行せず、パラメータの検証のみ行う

## トラブルシューティング

### Molecule テストが失敗する場合

```bash
# デバッグモードで実行
molecule --debug test

# ログを確認
cat /home/runner/.cache/molecule/default/default/ansible.log
```

### Docker コンテナにログインできない場合

```bash
# コンテナの状態を確認
docker ps -a

# 手動でコンテナを起動
docker run -it --rm --privileged geerlingguy/docker-ubuntu2204-ansible:latest /bin/bash
```

### ansible-lint エラー

`.ansible-lint` ファイルで特定のルールをスキップできます：

```yaml
skip_list:
  - command-instead-of-module
  - risky-shell-pipe
```

## 今後の拡張

- [ ] より詳細な統合テスト（kubeadm のモック実行）
- [ ] Testinfra による Python ベースのテスト
- [ ] パフォーマンステスト
- [ ] セキュリティスキャン（Trivy、Ansible Galaxy linter）
- [ ] リリース自動化

## 参考リンク

- [Molecule Documentation](https://molecule.readthedocs.io/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [ansible-lint Documentation](https://ansible-lint.readthedocs.io/)
- [ShellCheck](https://www.shellcheck.net/)
