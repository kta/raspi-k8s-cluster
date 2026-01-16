# トラブルシューティング

Proxmox HA Kubernetes Cluster で発生する可能性のある問題と解決方法をまとめています。

## 目次

- [Terraform 関連](#terraform-関連)
- [VM 起動関連](#vm-起動関連)
- [Kubernetes 関連](#kubernetes-関連)
- [ネットワーク関連](#ネットワーク関連)
- [Ceph ストレージ関連](#ceph-ストレージ関連)
- [ArgoCD 関連](#argocd-関連)

---

## Terraform 関連

### エラー: `Error: authentication failed`

**症状**:
```
Error: authentication failed
│ 
│   with provider["registry.terraform.io/bpg/proxmox"],
│   on providers.tf line 1, in provider "proxmox":
```

**原因**: Proxmox API トークンが正しくない、または権限不足

**解決方法**:
```bash
# 環境変数を確認
echo $PM_API_TOKEN_ID
echo $PM_API_TOKEN_SECRET

# Proxmox API トークンの権限を確認
# Proxmox UI: Datacenter → Permissions → API Tokens
# "Privilege Separation" のチェックが外れていることを確認

# 再度環境変数を設定
source .env
```

### エラー: `Error: downloaded file checksum mismatch`

**症状**: Debian Cloud Image のダウンロードでチェックサムエラー

**解決方法**:
```bash
# 既存のイメージを削除
ssh root@192.168.100.101 "rm -f /var/lib/vz/template/iso/debian-13-trixie-arm64.img"

# Terraform を再実行
terraform apply
```

### エラー: `VM already exists`

**症状**: VM ID が既に使用されている

**解決方法**:
```bash
# Proxmox で既存の VM を確認
ssh root@192.168.100.101 "qm list"

# 該当する VM を削除（必要に応じて）
ssh root@192.168.100.101 "qm destroy <VM_ID>"

# Terraform state をクリーンアップ
cd terraform
terraform state list
terraform state rm 'module.control_plane_vms[0]'  # 必要に応じて

# 再実行
terraform apply
```

---

## VM 起動関連

### VM が起動しない

**症状**: VM が作成されても起動しない、またはすぐに停止する

**確認方法**:
```bash
# Proxmox で VM のステータスを確認
ssh root@192.168.100.101 "qm status <VM_ID>"

# VM のログを確認
ssh root@192.168.100.101 "cat /var/log/qemu-server/<VM_ID>.log"
```

**原因と解決方法**:

1. **メモリ不足**
   ```bash
   # 物理ノードのメモリ使用状況を確認
   ssh root@192.168.100.101 "free -h"
   
   # VM のメモリを減らす（variables.tf で調整）
   vm_memory_mb = 1536  # 2048 → 1536
   ```

2. **Ceph ストレージが利用できない**
   ```bash
   # Ceph の状態を確認
   ssh root@192.168.100.101 "ceph -s"
   
   # Ceph プールを確認
   ssh root@192.168.100.101 "ceph osd pool ls"
   ```

3. **Cloud-Init が失敗している**
   ```bash
   # VM コンソールにアクセスして確認
   # Proxmox UI: VM → Console
   
   # Cloud-Init ログを確認（VM起動後）
   ssh debian@192.168.100.201 "sudo cat /var/log/cloud-init-output.log"
   ```

### SSH 接続ができない

**症状**: VM は起動しているが SSH 接続できない

**確認方法**:
```bash
# VM の IP に ping
ping 192.168.100.201

# SSH で接続試行（詳細ログ）
ssh -vvv debian@192.168.100.201
```

**原因と解決方法**:

1. **SSH 公開鍵が正しく設定されていない**
   ```bash
   # GitHub から SSH 鍵を確認
   curl https://github.com/YOUR_USERNAME.keys
   
   # VM コンソールから直接ログイン（Proxmox UI）
   # /home/debian/.ssh/authorized_keys を確認
   ```

2. **ネットワーク設定が正しくない**
   ```bash
   # VM コンソールでネットワーク設定を確認
   ip addr show
   ip route show
   
   # /etc/network/interfaces を確認
   cat /etc/network/interfaces
   ```

---

## Kubernetes 関連

### kubeadm init が失敗する

**症状**: 最初の Control Plane で kubeadm init がエラーになる

**確認方法**:
```bash
# Control Plane にSSH接続
ssh debian@192.168.100.201

# kubeadm ログを確認
sudo journalctl -xeu kubelet
```

**原因と解決方法**:

1. **スワップが有効になっている**
   ```bash
   # スワップを確認
   sudo swapon --show
   
   # スワップを無効化
   sudo swapoff -a
   sudo sed -i '/ swap / s/^/#/' /etc/fstab
   ```

2. **containerd が起動していない**
   ```bash
   # containerd の状態を確認
   sudo systemctl status containerd
   
   # containerd を再起動
   sudo systemctl restart containerd
   ```

3. **ポート 6443 が既に使用されている**
   ```bash
   # ポート使用状況を確認
   sudo netstat -tulpn | grep 6443
   
   # 既存の kubeadm をリセット
   sudo kubeadm reset -f
   ```

### ノードが Ready にならない

**症状**: `kubectl get nodes` で NotReady 状態

**確認方法**:
```bash
kubectl get nodes
kubectl describe node pve-vm-cp-1
```

**原因と解決方法**:

1. **CNI (Flannel) がインストールされていない**
   ```bash
   # CNI Pod の状態を確認
   kubectl get pods -n kube-flannel
   
   # Flannel を再インストール
   cd terraform
   terraform apply -target=helm_release.flannel
   ```

2. **kubelet が起動していない**
   ```bash
   # ノードに SSH 接続
   ssh debian@192.168.100.201
   
   # kubelet のログを確認
   sudo journalctl -xeu kubelet
   
   # kubelet を再起動
   sudo systemctl restart kubelet
   ```

### kube-vip が動作しない

**症状**: VIP (192.168.100.200) に接続できない

**確認方法**:
```bash
# VIP に疎通確認
curl -k https://192.168.100.200:6443/healthz

# kube-vip Pod の状態を確認
kubectl get pods -n kube-system | grep kube-vip
kubectl logs -n kube-system kube-vip-pve-vm-cp-1
```

**解決方法**:
```bash
# kube-vip マニフェストを確認
ssh debian@192.168.100.201 "sudo cat /etc/kubernetes/manifests/kube-vip.yaml"

# kube-vip を再起動
ssh debian@192.168.100.201 "sudo systemctl restart kubelet"
```

---

## ネットワーク関連

### Pod 間通信ができない

**症状**: Pod から別の Pod に接続できない

**確認方法**:
```bash
# テスト用 Pod を作成
kubectl run test-1 --image=busybox --command -- sleep 3600
kubectl run test-2 --image=busybox --command -- sleep 3600

# IP を確認
kubectl get pods -o wide

# Pod 間で ping
kubectl exec test-1 -- ping <test-2-ip>
```

**解決方法**:

1. **Flannel が正常に動作していない**
   ```bash
   # Flannel Pod のログを確認
   kubectl logs -n kube-flannel -l app=flannel
   
   # ネットワークポリシーを確認
   kubectl get networkpolicies -A
   ```

2. **iptables ルールの問題**
   ```bash
   # ノードに接続
   ssh debian@192.168.100.201
   
   # iptables を確認
   sudo iptables -L -n -v
   
   # IP フォワーディングを確認
   sudo sysctl net.ipv4.ip_forward
   # 1 であること
   ```

### DNS 解決ができない

**症状**: Pod 内から Service 名で名前解決できない

**確認方法**:
```bash
# CoreDNS の状態を確認
kubectl get pods -n kube-system -l k8s-app=kube-dns

# DNS テスト
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default
```

**解決方法**:
```bash
# CoreDNS を再起動
kubectl rollout restart deployment/coredns -n kube-system

# CoreDNS ログを確認
kubectl logs -n kube-system -l k8s-app=kube-dns
```

---

## Ceph ストレージ関連

### VM ディスクの作成が失敗する

**症状**: Terraform で VM 作成時にディスクエラーが発生

**確認方法**:
```bash
# Ceph の状態を確認
ssh root@192.168.100.101 "ceph -s"

# Ceph プールの容量を確認
ssh root@192.168.100.101 "ceph df"
```

**解決方法**:

1. **Ceph が HEALTH_WARN または HEALTH_ERR**
   ```bash
   # 詳細な警告を確認
   ssh root@192.168.100.101 "ceph health detail"
   
   # OSD の状態を確認
   ssh root@192.168.100.101 "ceph osd tree"
   ```

2. **ストレージ容量不足**
   ```bash
   # ディスクサイズを減らす（variables.tf）
   vm_disk_size_gb = 10  # 20 → 10
   
   # または不要な VM を削除
   ```

---

## ArgoCD 関連

### ArgoCD にアクセスできない

**症状**: Port Forward が失敗する、またはログインできない

**確認方法**:
```bash
# ArgoCD Pod の状態を確認
kubectl get pods -n argocd

# ArgoCD Server のログを確認
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
```

**解決方法**:

1. **ArgoCD がインストールされていない**
   ```bash
   # Helm Release を確認
   helm list -n argocd
   
   # 再インストール
   cd terraform
   terraform apply -target=module.argocd
   ```

2. **初期パスワードが取得できない**
   ```bash
   # Secret を手動で確認
   kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d
   ```

---

## よくある質問

### Q: Terraform destroy でエラーが出る

**A**: VM を手動で削除した場合、Terraform state が不整合になることがあります。

```bash
# State を確認
terraform state list

# 削除済みリソースを state から削除
terraform state rm 'module.control_plane_vms[0]'

# 再度 destroy
terraform destroy
```

### Q: クラスター全体を再構築したい

**A**: 以下の手順で完全にクリーンアップできます。

```bash
# Terraform で削除
cd terraform
terraform destroy

# Proxmox で残存 VM を確認・削除
ssh root@192.168.100.101 "qm list"
ssh root@192.168.100.101 "qm destroy <VM_ID>"

# Ceph ストレージをクリーンアップ（オプション）
ssh root@192.168.100.101 "rbd ls ceph-vm"
ssh root@192.168.100.101 "rbd rm ceph-vm/<image-name>"

# 再構築
terraform apply
```

---

## サポート

上記で解決しない場合は、以下の情報を添えて Issue を作成してください：

- エラーメッセージ全文
- `terraform version`
- `kubectl version`
- `ceph -s` の出力
- 関連するログファイル
