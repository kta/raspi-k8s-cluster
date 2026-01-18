# Ansible Directory - Phase 1: OS設定 & Kubeadm構築

このディレクトリには、Raspberry PiクラスターのOS設定とKubernetesクラスターの初期構築に関するAnsible Playbookが含まれています。

## ディレクトリ構造

```
ansible/
├── inventory/
│   ├── inventory.ini          # 本番環境のインベントリ
│   └── inventory_vagrant.ini  # Vagrant環境のインベントリ
├── roles/
│   ├── common/                # swap無効化, cgroup設定(重要), 依存パッケージ
│   ├── container-runtime/     # containerd のインストール & 設定
│   └── kubeadm/               # kubeadm init/join の実行
├── site.yml                   # メインPlaybook
├── fetch-kubeconfig.yml       # ★ admin.confを持ってくる専用Playbook
├── reset.yml                  # クラスターリセット用
├── upgrade.yml                # クラスターアップグレード用
└── verify.yml                 # クラスター検証用
```

## 使い方

```bash
# クラスター構築
make ansible-setup

# kubeconfigの取得
make fetch-kubeconfig

# クラスター検証
ansible-playbook -i inventory/inventory.ini verify.yml
```
