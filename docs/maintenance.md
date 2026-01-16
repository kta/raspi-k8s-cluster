# メンテナンスガイド

Proxmox HA Kubernetes Cluster の運用・メンテナンス手順をまとめています。

## 目次

- [定期メンテナンス](#定期メンテナンス)
- [VM の管理](#vm-の管理)
- [Kubernetes のアップグレード](#kubernetes-のアップグレード)
- [ストレージ管理](#ストレージ管理)
- [バックアップとリストア](#バックアップとリストア)
- [監視とアラート](#監視とアラート)

---

## 定期メンテナンス

### 週次チェックリスト

```bash
# 1. Ceph ヘルスチェック
ssh root@192.168.100.101 "ceph -s"
# HEALTH_OK であることを確認

# 2. Kubernetes ノードの状態確認
kubectl get nodes
# 全ノードが Ready であることを確認

# 3. Pod の状態確認
kubectl get pods -A | grep -v Running | grep -v Completed

# 4. Ceph ストレージ使用率確認
ssh root@192.168.100.101 "ceph df"
# 使用率が80%を超えていないか確認

# 5. VM のリソース使用状況
ssh root@192.168.100.101 "pvesh get /nodes/pi-node-1/qemu --output-format=json" | jq
```

### 月次チェックリスト

```bash
# 1. システムアップデート（Control Plane と Worker）
for ip in 192.168.100.201 192.168.100.202 192.168.100.203 192.168.100.211 192.168.100.212 192.168.100.213; do
  echo "Updating $ip..."
  ssh debian@$ip "sudo apt update && sudo apt upgrade -y"
done

# 2. containerd のログローテーション確認
ssh debian@192.168.100.201 "sudo journalctl --disk-usage"

# 3. Ceph のスクラブ状況確認
ssh root@192.168.100.101 "ceph pg dump | grep -i scrub"

# 4. バックアップの実行（後述）
```

---

## VM の管理

### Worker ノードの追加

新しい Worker ノードを追加する手順：

**1. variables.tf を編集**

```hcl
variable "worker_ips" {
  default     = ["192.168.100.211", "192.168.100.212", "192.168.100.213", "192.168.100.214"]  # 追加
}

variable "worker_hostnames" {
  default     = ["pve-vm-wk-1", "pve-vm-wk-2", "pve-vm-wk-3", "pve-vm-wk-4"]  # 追加
}
```

**2. Terraform を適用**

```bash
cd terraform
terraform plan
terraform apply
```

**3. ノードの確認**

```bash
kubectl get nodes
# pve-vm-wk-4 が追加されていることを確認
```

### Worker ノードの削除

**1. ノードを drain**

```bash
# Pod を安全に退避
kubectl drain pve-vm-wk-3 --ignore-daemonsets --delete-emptydir-data

# ノードを削除
kubectl delete node pve-vm-wk-3
```

**2. variables.tf からエントリを削除**

```hcl
variable "worker_ips" {
  default     = ["192.168.100.211", "192.168.100.212"]  # .213 を削除
}

variable "worker_hostnames" {
  default     = ["pve-vm-wk-1", "pve-vm-wk-2"]  # wk-3 を削除
}
```

**3. Terraform を適用**

```bash
terraform apply
```

### VM のリソース変更

**CPU / メモリの変更**:

```hcl
# variables.tf
variable "vm_cpu_cores" {
  default     = 4  # 2 → 4
}

variable "vm_memory_mb" {
  default     = 4096  # 2048 → 4096
}
```

```bash
terraform apply
```

**注意**: リソース変更には VM の再起動が必要です。Control Plane は1台ずつ変更してください。

---

## Kubernetes のアップグレード

### マイナーバージョンアップ (例: v1.35 → v1.36)

**重要**: 一度に1つのマイナーバージョンのみアップグレード可能です。

**1. Control Plane のアップグレード（1台目）**

```bash
ssh debian@192.168.100.201

# パッケージリストを更新
sudo apt update

# 利用可能なバージョンを確認
sudo apt-cache madison kubeadm | grep 1.36

# kubeadm をアップグレード
sudo apt-mark unhold kubeadm
sudo apt install -y kubeadm=1.36.0-1.1
sudo apt-mark hold kubeadm

# アップグレードプランを確認
sudo kubeadm upgrade plan

# アップグレード実行
sudo kubeadm upgrade apply v1.36.0

# kubelet と kubectl をアップグレード
sudo apt-mark unhold kubelet kubectl
sudo apt install -y kubelet=1.36.0-1.1 kubectl=1.36.0-1.1
sudo apt-mark hold kubelet kubectl

# kubelet を再起動
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

**2. Control Plane のアップグレード（2台目・3台目）**

```bash
# 各ノードで実行
ssh debian@192.168.100.202

sudo apt update
sudo apt-mark unhold kubeadm kubelet kubectl
sudo apt install -y kubeadm=1.36.0-1.1 kubelet=1.36.0-1.1 kubectl=1.36.0-1.1
sudo apt-mark hold kubeadm kubelet kubectl

sudo kubeadm upgrade node

sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

**3. Worker ノードのアップグレード**

```bash
# ローカルから drain
kubectl drain pve-vm-wk-1 --ignore-daemonsets --delete-emptydir-data

# Worker にSSH接続
ssh debian@192.168.100.211

sudo apt update
sudo apt-mark unhold kubeadm kubelet kubectl
sudo apt install -y kubeadm=1.36.0-1.1 kubelet=1.36.0-1.1 kubectl=1.36.0-1.1
sudo apt-mark hold kubeadm kubelet kubectl

sudo kubeadm upgrade node

sudo systemctl daemon-reload
sudo systemctl restart kubelet

# ローカルに戻って uncordon
kubectl uncordon pve-vm-wk-1
```

**4. 全ノードで繰り返し**

Worker 2, 3 も同様に実行。

**5. 確認**

```bash
kubectl get nodes
# 全ノードが v1.36.0 であることを確認
```

### パッチバージョンアップ (例: v1.35.0 → v1.35.1)

各ノードで以下を実行：

```bash
ssh debian@192.168.100.201

sudo apt update
sudo apt upgrade -y kubeadm kubelet kubectl
sudo systemctl restart kubelet
```

---

## ストレージ管理

### Ceph 容量の確認

```bash
# 全体の使用状況
ssh root@192.168.100.101 "ceph df"

# プールごとの詳細
ssh root@192.168.100.101 "ceph osd pool stats ceph-vm"

# OSD ごとの使用率
ssh root@192.168.100.101 "ceph osd df tree"
```

### OSD の追加（容量拡張）

新しい USB SSD を追加する場合：

```bash
# 物理ノードに SSH 接続
ssh root@192.168.100.101

# 新しいディスクを確認
lsblk

# OSD を作成（例: /dev/sdc）
ceph-volume lvm create --data /dev/sdc

# OSD の状態を確認
ceph osd tree
```

### 不要な VM ディスクの削除

```bash
# Ceph 内の RBD イメージを確認
ssh root@192.168.100.101 "rbd ls ceph-vm"

# 不要なイメージを削除
ssh root@192.168.100.101 "rbd rm ceph-vm/<image-name>"
```

---

## バックアップとリストア

### etcd のバックアップ（Kubernetes データ）

**1. バックアップスクリプトの作成**

```bash
# Control Plane にSSH接続
ssh debian@192.168.100.201

cat << 'EOF' > /home/debian/backup-etcd.sh
#!/bin/bash
BACKUP_DIR="/home/debian/etcd-backup"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p $BACKUP_DIR

sudo ETCDCTL_API=3 etcdctl snapshot save $BACKUP_DIR/etcd-snapshot-$TIMESTAMP.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

echo "Backup completed: $BACKUP_DIR/etcd-snapshot-$TIMESTAMP.db"

# 古いバックアップを削除（7日以上前）
find $BACKUP_DIR -name "etcd-snapshot-*.db" -mtime +7 -delete
EOF

chmod +x /home/debian/backup-etcd.sh
```

**2. cron で定期実行**

```bash
# crontab に追加（毎日午前3時）
(crontab -l 2>/dev/null; echo "0 3 * * * /home/debian/backup-etcd.sh") | crontab -
```

**3. バックアップの確認**

```bash
ls -lh /home/debian/etcd-backup/
```

### etcd のリストア

**警告**: クラスター全体が停止します。緊急時のみ実行してください。

```bash
# Control Plane 1台目にSSH接続
ssh debian@192.168.100.201

# etcd を停止
sudo systemctl stop kubelet
sudo mv /etc/kubernetes/manifests/etcd.yaml /tmp/

# リストア実行
sudo ETCDCTL_API=3 etcdctl snapshot restore /home/debian/etcd-backup/etcd-snapshot-XXXXXXXX.db \
  --data-dir=/var/lib/etcd-restore

# 既存のデータを置き換え
sudo rm -rf /var/lib/etcd
sudo mv /var/lib/etcd-restore /var/lib/etcd

# etcd を再起動
sudo mv /tmp/etcd.yaml /etc/kubernetes/manifests/
sudo systemctl start kubelet

# 確認
kubectl get nodes
```

### VM のスナップショット

Proxmox の機能を使用：

```bash
# スナップショット作成
ssh root@192.168.100.101 "qm snapshot <VM_ID> <snapshot-name>"

# スナップショット一覧
ssh root@192.168.100.101 "qm listsnapshot <VM_ID>"

# ロールバック
ssh root@192.168.100.101 "qm rollback <VM_ID> <snapshot-name>"

# スナップショット削除
ssh root@192.168.100.101 "qm delsnapshot <VM_ID> <snapshot-name>"
```

---

## 監視とアラート

### Prometheus + Grafana のインストール

ArgoCD 経由でインストール（推奨）：

```bash
# ArgoCD で monitoring アプリケーションを登録
# （フェーズ9で実装予定）
```

### 基本的な監視項目

**1. ノードのリソース使用率**

```bash
# CPU/メモリ使用率
kubectl top nodes

# Pod のリソース使用率
kubectl top pods -A
```

**2. Ceph の監視**

```bash
# ヘルスステータス
ssh root@192.168.100.101 "ceph -s"

# 容量アラート（80%以上）
ssh root@192.168.100.101 "ceph df | awk '\$5 > 80 {print \$0}'"
```

**3. ログの確認**

```bash
# Control Plane のログ
kubectl logs -n kube-system -l component=kube-apiserver --tail=100

# CoreDNS のログ
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=100

# Flannel のログ
kubectl logs -n kube-flannel -l app=flannel --tail=100
```

---

## 緊急時の対応

### Control Plane が1台ダウンした場合

**症状**: 3台のうち1台が NotReady

**対応**:
```bash
# ノードの状態を確認
kubectl get nodes

# ダウンしたノードを確認
kubectl describe node pve-vm-cp-2

# 定足数は維持されているため、クラスターは稼働継続
# VM を再起動
ssh root@192.168.100.102 "qm start <VM_ID>"

# 復旧後、ノードが Ready になることを確認
kubectl get nodes
```

### Control Plane が2台以上ダウンした場合

**警告**: クラスターが停止します。

**対応**:
1. 速やかにダウンしたノードを復旧
2. etcd の定足数が復旧するまで待機
3. 復旧しない場合は、etcd バックアップからリストア

### Ceph が HEALTH_ERR の場合

```bash
# 詳細を確認
ssh root@192.168.100.101 "ceph health detail"

# OSD の状態を確認
ssh root@192.168.100.101 "ceph osd tree"

# ダウンした OSD を再起動
ssh root@192.168.100.101 "systemctl restart ceph-osd@<OSD_ID>"
```

---

## 参考資料

- [Kubernetes 公式ドキュメント - クラスター管理](https://kubernetes.io/docs/tasks/administer-cluster/)
- [Ceph 公式ドキュメント](https://docs.ceph.com/)
- [Proxmox VE 管理ガイド](https://pve.proxmox.com/pve-docs/)
