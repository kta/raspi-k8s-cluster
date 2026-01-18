# Molecule テスティングガイド

## Molecule とは

Molecule は Ansible ロールとプレイブックをテストするためのフレームワークです。Docker、Vagrant、Podman などの様々なドライバーをサポートしています。

## アーキテクチャ

### テスト環境

```
┌─────────────────────────────────────────────────────┐
│ GitHub Actions Runner (Ubuntu)                      │
│                                                      │
│  ┌──────────────────────────────────────────────┐  │
│  │ Docker Network: molecule-k8s-net             │  │
│  │                                               │  │
│  │  ┌──────────────┐  ┌──────────────┐          │  │
│  │  │ primary-     │  │ secondary-   │          │  │
│  │  │ master       │  │ master-1     │          │  │
│  │  │ (systemd)    │  │ (systemd)    │          │  │
│  │  │ 172.18.0.2   │  │ 172.18.0.3   │          │  │
│  │  └──────────────┘  └──────────────┘          │  │
│  │                                               │  │
│  │  ┌──────────────┐                            │  │
│  │  │ secondary-   │                            │  │
│  │  │ master-2     │                            │  │
│  │  │ (systemd)    │                            │  │
│  │  │ 172.18.0.4   │                            │  │
│  │  └──────────────┘                            │  │
│  └──────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

### systemd 対応コンテナ

通常の Docker コンテナは systemd を実行できませんが、以下の設定により可能になります：

```yaml
platforms:
  - name: primary-master
    image: geerlingguy/docker-ubuntu2204-ansible:latest
    command: /lib/systemd/systemd          # systemd を PID 1 として起動
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:rw   # cgroup をマウント
    cgroupns_mode: host                     # ホストの cgroup を使用
    privileged: true                        # 特権モード
```

## テストシナリオ

### 1. Prepare（準備）

**ファイル**: `molecule/default/prepare.yml`

- apt キャッシュの更新
- Python 依存関係のインストール
- systemd の確認
- 必要なディレクトリの作成
- ホスト名と /etc/hosts の設定

### 2. Converge（実行）

**ファイル**: `molecule/default/converge.yml`

- スクリプトのコピー
- 実行権限の確認
- containerd のインストール（依存関係テスト）
- パラメータの検証

**注意**: 実際の `kubeadm init` や `kubeadm join` は実行しません。これらはフルスタックの Kubernetes クラスタが必要であり、CI 環境では実行が困難です。

### 3. Verify（検証）

**ファイル**: `molecule/default/verify.yml`

検証項目：
- ✅ スクリプトの存在確認
- ✅ 実行権限の確認
- ✅ containerd のインストール確認
- ✅ ネットワークインターフェースの確認
- ✅ ノードロール（primary/secondary）の確認

## 実行シーケンス

```bash
molecule test
```

実行される順序：
1. **dependency**: Ansible Galaxy から依存ロールをインストール
2. **cleanup**: 以前のテストの後片付け
3. **destroy**: 既存のコンテナを削除
4. **syntax**: Playbook の構文チェック
5. **create**: Docker コンテナを作成
6. **prepare**: テスト環境を準備
7. **converge**: Ansible Playbook を実行
8. **idempotence**: 冪等性テスト（同じ実行で変更が発生しないか）
9. **side_effect**: サイドエフェクトテスト（オプション）
10. **verify**: 検証テストを実行
11. **cleanup**: 後片付け
12. **destroy**: コンテナを削除

## カスタマイズ

### インベントリ変数

`molecule.yml` の `provisioner.inventory` セクションで変数を定義：

```yaml
provisioner:
  name: ansible
  inventory:
    group_vars:
      all:
        k8s_version: "1.35"
        vip: "172.18.0.100"
        interface: "eth0"
        haproxy_port: "8443"
        node_ips: "172.18.0.2,172.18.0.3,172.18.0.4"
        ci_mode: true  # CI モードフラグ
    host_vars:
      primary-master:
        priority: 101
        state: MASTER
```

### CI モードの活用

スクリプト内で `ci_mode` 変数をチェックし、CI 環境では実行をスキップする：

```bash
# common_setup.sh の例
if [ "${CI_MODE:-false}" = "true" ]; then
    echo "CI mode detected, skipping actual kubeadm installation"
    exit 0
fi
```

## デバッグ方法

### コンテナにログイン

```bash
# Molecule でコンテナを作成
molecule create

# コンテナにログイン
molecule login -h primary-master

# 手動でコマンドを実行
ansible@primary-master:~$ systemctl status
ansible@primary-master:~$ cat /tmp/common_setup.sh
```

### ログの確認

```bash
# Molecule のログ
cat ~/.cache/molecule/default/default/ansible.log

# デバッグモードで実行
molecule --debug converge
```

### 手動でコンテナを起動

```bash
docker run -it --rm --privileged \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --cgroupns=host \
  geerlingguy/docker-ubuntu2204-ansible:latest \
  /bin/bash
```

## ベストプラクティス

### 1. テストの範囲を明確にする

- ✅ スクリプトの配置と権限
- ✅ 基本的な依存関係のインストール
- ✅ 設定ファイルの生成
- ❌ 完全な Kubernetes クラスタの構築（CI では困難）

### 2. 冪等性を保つ

Ansible タスクは何度実行しても同じ結果になるようにします：

```yaml
- name: Install containerd
  apt:
    name: containerd.io
    state: present
  # 冪等性: すでにインストールされている場合は何もしない
```

### 3. CI 専用のロジックを分離

```yaml
# converge.yml
- name: Run common setup (CI mode - dry run only)
  debug:
    msg: "Would run: /tmp/common_setup.sh {{ vip }} {{ interface }} ..."
  when: ci_mode | default(false)

- name: Run common setup (production)
  shell: /tmp/common_setup.sh {{ vip }} {{ interface }} ...
  when: not (ci_mode | default(false))
```

### 4. エラーハンドリング

```yaml
- name: Check if scripts are executable
  stat:
    path: "/tmp/{{ item }}"
  register: script_stats
  failed_when: not script_stats.stat.exists or not script_stats.stat.executable
  loop:
    - common_setup.sh
    - primary_init.sh
```

## 制限事項と今後の改善

### 現在の制限

1. **完全なクラスタ構築は不可**: kubeadm init/join の実際の実行は行わない
2. **ネットワーク制約**: VIP（Keepalived）の完全なテストは困難
3. **リソース制限**: GitHub Actions の実行時間とリソース

### 今後の改善案

1. **Kind（Kubernetes in Docker）の利用**: 軽量な Kubernetes クラスタを CI 上で構築
2. **モックの導入**: kubeadm コマンドをモック化してテスト
3. **段階的なテスト**: Phase 1（OS設定）と Phase 2（K8s セットアップ）を分離
4. **Testinfra の活用**: Python ベースのより詳細なテスト

## 参考コマンド

```bash
# 全テストシーケンスを実行
molecule test

# ステップごとに実行
molecule create
molecule prepare
molecule converge
molecule verify
molecule destroy

# 特定のシナリオを実行
molecule test --scenario-name default

# 並列実行
molecule test --parallel

# コンテナを残したまま終了（デバッグ用）
molecule converge
# ... デバッグ ...
molecule destroy
```

## まとめ

Molecule を使用することで、実際のハードウェアや VM を使用せずに Ansible プレイブックをテストできます。完全な Kubernetes クラスタの構築は CI 環境では困難ですが、スクリプトの配置、依存関係のインストール、基本的な設定の検証は十分に可能です。

このアプローチにより、コードの品質を保ちながら、迅速なフィードバックループを実現できます。
