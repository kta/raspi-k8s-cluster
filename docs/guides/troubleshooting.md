# トラブルシューティング

## Flannel CNI - Pod間通信の問題

### 症状
- Pod間の通信がタイムアウトする
- CoreDNSがアクセスできない
- `dial udp 10.96.0.10:53: i/o timeout` エラーが発生
- `ping` テストが失敗する

### 原因
Flannelが間違ったネットワークインターフェースを使用している。

**Vagrant環境**: 
- デフォルトで `eth0` (NAT: 10.0.2.x) を使用するが、実際には `eth1` (プライベートネットワーク: 192.168.56.x) を使うべき

**実機環境**:
- 複数のネットワークインターフェースがある場合、正しいものを指定する必要がある

### 解決方法

#### 1. インベントリファイルでインターフェースを指定

`ansible/inventory/*.ini` で `interface` 変数を設定：

```ini
# Vagrant環境
interface=eth1

# 実機環境（例）
interface=eth0
```

#### 2. Flannelマニフェストの確認

`k8s/infra/cni/kube-flannel.yml` の `args` セクションに `--iface` が含まれていることを確認：

```yaml
containers:
- name: kube-flannel
  args:
  - --ip-masq
  - --kube-subnet-mgr
  - --iface=eth1  # ← このパラメータが必要
```

#### 3. デプロイメント方法

Flannelは2段階でデプロイされます：

**初回構築時**（ArgoCDがまだ存在しない）:
- `ansible/scripts/primary_init.sh` が `interface` 変数から動的にパッチを適用
- マニフェストを直接 `kubectl apply`

**ArgoCD管理後**:
- `k8s/infra/cni/flannel.yaml` (ArgoCD Application) で管理
- リポジトリ: `k8s/infra/cni/` ディレクトリ
- 自動同期・セルフヒール有効

#### 4. 既存クラスタの修正

既にクラスタが稼働中の場合：

```bash
# DaemonSetに --iface を追加
kubectl patch ds -n kube-flannel kube-flannel-ds --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--iface=eth1"}]'

# ロールアウトの完了を確認
kubectl rollout status ds/kube-flannel-ds -n kube-flannel

# Pod間通信をテスト
kubectl run ping-test --image=busybox:1.36 --rm -it --restart=Never -- \
  sh -c 'ping -c 3 10.244.1.1 && echo "SUCCESS"'
```

### 検証コマンド

```bash
# Flannelインターフェースの確認
kubectl exec -n kube-flannel -it kube-flannel-ds-xxxxx -- \
  ip -d link show flannel.1

# 正しいIPアドレスが使われているか確認（192.168.56.x であるべき）
kubectl exec -n kube-flannel -it kube-flannel-ds-xxxxx -- \
  ip addr show flannel.1

# Pod間通信のテスト
kubectl run net-test --image=nicolaka/netshoot --rm -it --restart=Never -- \
  ping -c 3 <他のPodのIP>

# ArgoCD Application の状態確認
kubectl get app -n argocd cni-flannel
argocd app get cni-flannel
```

### ファイル構成

```
k8s/infra/cni/
├── flannel.yaml          # ArgoCD Application定義
├── kube-flannel.yml      # Flannelマニフェスト (--iface含む)
└── kustomization.yaml    # Kustomize設定

ansible/
├── inventory/
│   ├── inventory.ini     # 実機用: interface=eth0
│   └── inventory_vagrant.ini  # Vagrant用: interface=eth1
├── scripts/
│   └── primary_init.sh   # 初回構築時にマニフェストをパッチ適用
└── site.yml              # マニフェストをノードにコピー
```

### 参考情報

- [Flannel公式ドキュメント](https://github.com/flannel-io/flannel)
- [Flannel Configuration](https://github.com/flannel-io/flannel/blob/master/Documentation/configuration.md)

## ArgoCD - Repository Server のクラッシュ

### 症状
- `argocd-repo-server` が `CrashLoopBackOff` 状態
- `Liveness probe failed` エラー
- `argocd app sync` が失敗

### 原因
ARM64環境でのメモリ不足またはliveness probeのタイムアウト

### 解決方法

`terraform/bootstrap/argocd-values.yaml` でリソース制限を調整：

```yaml
repoServer:
  resources:
    requests:
      cpu: 100m
      memory: 256Mi  # デフォルトの128Miから増量
    limits:
      cpu: 1000m
      memory: 512Mi  # デフォルトの256Miから増量

  livenessProbe:
    initialDelaySeconds: 30  # 起動に時間がかかるため延長
    timeoutSeconds: 10
```

変更後、Terraformで再適用：

```bash
cd terraform/bootstrap
terraform apply
```

## 参考リンク

- [プロジェクトREADME](../README.md)
- [ArgoCD Values](./argocd/values.yaml)
- [Ansible Playbook](../ansible/site.yml)
