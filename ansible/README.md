# Ansible Directory - Phase 1: OS設定 & Kubeadm構築

このディレクトリには、Raspberry Piクラスターの物理層（OS設定）から Kubernetes クラスターの初期構築（Kubeadm）までを担当する Ansible Playbook が含まれています。

本プロジェクトの **基盤（Foundation）** を構築するフェーズです。

## 📂 ディレクトリ構造

```text
ansible/
├── inventory/
│   ├── inventory.ini          # 🟢 本番環境 (Raspberry Pi) 用インベントリ
│   └── inventory_vagrant.ini  # 🔵 テスト環境 (Vagrant) 用インベントリ
├── roles/
│   ├── common/                # 共通設定 (Swap無効化, cgroup設定, 必須pkg)
│   ├── container-runtime/     # コンテナランタイム (containerd) の導入
│   └── kubeadm/               # クラスタ構築 (init / join)
├── scripts/                   # 構築ロジック (ShellScript)
├── site.yml                   # メイン Playbook
├── fetch-kubeconfig.yml       # admin.conf をローカルに取得する Playbook
├── reset.yml                  # クラスタ初期化・削除用
├── upgrade.yml                # バージョンアップ用
└── verify.yml                 # 構築後の動作検証用

```

## 🏗 アーキテクチャ概要

本クラスタは、**ハイパーコンバージド構成** かつ **完全な高可用性 (HA)** を備えています。

### 1. ノード構成 (Node Topology)

3台の Raspberry Pi 全てにおいて、**Master Role (管理機能)** と **Worker Role (計算リソース)** が同居しています。

* **Master Role (青):** クラスタの制御、API提供、データ保存 (Etcd)
* **Worker Role (橙):** ユーザーアプリケーションの実行

これにより、どのノードがダウンしても管理機能・アプリ実行の両方が維持されます。

```mermaid
graph TB
    %% --- Node 1 ---
    subgraph N1 [<b>pi-node1</b>]
        direction TB
        M1[<b>Master Role</b><br/>Control Plane]
        W1[<b>Worker Role</b><br/>Workloads]
    end

    %% --- Node 2 ---
    subgraph N2 [<b>pi-node2</b>]
        direction TB
        M2[<b>Master Role</b><br/>Control Plane]
        W2[<b>Worker Role</b><br/>Workloads]
    end

    %% --- Node 3 ---
    subgraph N3 [<b>pi-node3</b>]
        direction TB
        M3[<b>Master Role</b><br/>Control Plane]
        W3[<b>Worker Role</b><br/>Workloads]
    end

    %% --- 配置関係 ---
    %% 上下関係を明確にするためのリンク（非表示）
    M1 --- W1
    M2 --- W2
    M3 --- W3

    %% --- スタイル定義 ---
    %% Master = 青系, Worker = オレンジ系
    classDef master fill:#bbdefb,stroke:#0d47a1,stroke-width:2px;
    classDef worker fill:#ffe0b2,stroke:#e65100,stroke-width:2px;
    classDef node fill:#f5f5f5,stroke:#333,stroke-width:1px;

    class M1,M2,M3 master;
    class W1,W2,W3 worker;
    class N1,N2,N3 node;

```

### 2. 高可用性とトラフィックフロー (HA & Traffic Flow)

**Keepalived (VRRP)** と **HAProxy** を全ノードに配置することで、単一障害点 (SPOF) を排除しています。

* **VIP (仮想IP):** ユーザーは常に VIP (`192.168.1.100`) にアクセスします。
* **Failover:** 現在のマスターがダウンすると、VIPは即座に別ノードへ移動します。
* **Load Balancing:** HAProxy は自分自身を含む「生きている全ノード」の API Server にリクエストを分散します。

```mermaid
graph TD
    %% --- User ---
    User([User / kubectl]) -->|Access VIP: 192.168.1.100| VIP
    style VIP fill:#f96,stroke:#333,stroke-width:2px
    
    VIP("Virtual IP (Floating)")

    %% --- Node 1 ---
    subgraph Node1 [pi-node1]
        direction TB
        KP1["Keepalived<br/>(Check: OK)"]
        HP1["HAProxy<br/>(Active)"]
        K8S1["API Server"]
        ETCD1[("Etcd")]
    end

    %% --- Node 2 ---
    subgraph Node2 [pi-node2]
        direction TB
        KP2["Keepalived<br/>(Check: OK)"]
        HP2["HAProxy<br/>(Active)"]
        K8S2["API Server"]
        ETCD2[("Etcd")]
    end

    %% --- Node 3 ---
    subgraph Node3 [pi-node3]
        direction TB
        KP3["Keepalived<br/>(Check: OK)"]
        HP3["HAProxy<br/>(Active)"]
        K8S3["API Server"]
        ETCD3[("Etcd")]
    end

    %% === 通信の流れ ===
    %% 1. VIPは「今リーダーの人のKeepalived」にくっつく
    VIP -.->|Normally attached to| KP1
    VIP -.->|Failover path| KP2
    VIP -.->|Failover path| KP3

    %% 2. KeepalivedからHAProxyへ (Localhost経由)
    KP1 --> HP1
    KP2 --> HP2
    KP3 --> HP3

    %% 3. HAProxyは「全員」に振り分ける (ここが重要！)
    HP1 ==x K8S1
    HP1 ==x K8S2
    HP1 ==x K8S3

    HP2 ==x K8S1
    HP2 ==x K8S2
    HP2 ==x K8S3

    HP3 ==x K8S1
    HP3 ==x K8S2
    HP3 ==x K8S3

    %% Note
    classDef plain fill:#fff,stroke:#333,stroke-width:1px;
    class Node1,Node2,Node3 plain;

```

## 🚀 使い方

プロジェクトルートの `Makefile` を使用することで、簡単に実行できます。

### Step 1: インベントリの編集

ご自身の環境に合わせて IP アドレス等を設定してください。

```bash
vi ansible/inventory/inventory.ini
```

### Step 2: 構築の実行 (Provisioning)

Ansible を実行し、OS 設定から K3s/K8s の起動までを行います。

```bash
make ansible-setup
```

### Step 3: 接続設定の取得 (Fetch Kubeconfig)

クラスターの管理者権限ファイル (`admin.conf`) を取得し、手元の PC から `kubectl` できるようにします。

```bash
make fetch-kubeconfig
```

### Step 4: 動作検証 (Verify)

全ノードが Ready か、HA 構成が機能しているかをテストします。

```bash
ansible-playbook -i inventory/inventory.ini verify.yml
```