# Kubernetes クラスタ監視ガイド

## 概要

このクラスタには **kube-prometheus-stack** が導入されており、包括的な監視環境を提供します。

### コンポーネント

| コンポーネント | 役割 | アクセス |
|--------------|------|----------|
| **Prometheus** | メトリクス収集・保存 | `http://localhost:9090` (port-forward) |
| **Grafana** | メトリクス可視化 | `https://grafana.raspi.local` or `https://grafana.vagrant.local` |
| **Alertmanager** | アラート管理 | `http://localhost:9093` (port-forward) |
| **node-exporter** | ノードメトリクス収集 | 各ノードで自動実行 |
| **kube-state-metrics** | K8sリソースメトリクス | 自動収集 |

## クイックスタート

### 1. Grafana UIへのアクセス

**方法A: Ingress経由（推奨 - Production）**
```bash
# /etc/hosts 設定（初回のみ）
make setup-local-dns ENV=production  # または ENV=vagrant

# ブラウザでアクセス
# Production: https://grafana.raspi.local
# Vagrant:    https://grafana.vagrant.local
```

**方法B: 直接アクセス（Vagrant環境のみ）**
```bash
# Vagrant環境では自動的にNodePortが設定されます
# ブラウザで直接アクセス:
# http://localhost:3000  (Grafana)
# http://localhost:9090  (Prometheus)
# http://localhost:9093  (Alertmanager)
```

**方法C: ポートフォワード**
```bash
make port-forward-grafana

# ブラウザで開く: http://localhost:3000
```

**初回ログイン**
- ユーザー名: `admin`
- パスワード: `admin`（初回ログイン後に変更を推奨）

### 2. Prometheusへのアクセス

**Vagrant環境（直接アクセス）:**
```bash
# ブラウザで開く: http://localhost:9090
```

**Production環境（ポートフォワード）:**
```bash
make port-forward-prometheus

# ブラウザで開く: http://localhost:9090
```

### 3. 全監視サービスへのアクセス

**Vagrant環境（直接アクセス）:**
```bash
# 自動的にNodePortが設定され、以下のURLで直接アクセス可能:
# - Grafana:       http://localhost:3000
# - Prometheus:    http://localhost:9090
# - Alertmanager:  http://localhost:9093
# - ArgoCD:        http://localhost:30080
# - Traefik:       http://localhost:9000 (port-forward必要)
```

**Production環境（ポートフォワード）:**
```bash
make port-forward-all

# 利用可能なサービス:
# - Grafana:       http://localhost:3000
# - Prometheus:    http://localhost:9090
# - Alertmanager:  http://localhost:9093
# - ArgoCD:        http://localhost:8080
# - Traefik:       http://localhost:9000
```

## デフォルトダッシュボード

Grafanaには以下のダッシュボードが自動でインポートされます：

### クラスタ全体
- **Kubernetes / Compute Resources / Cluster**: クラスタ全体のCPU・メモリ使用量
- **Kubernetes / Networking / Cluster**: ネットワークトラフィック統計

### ノード監視
- **Node Exporter / Nodes**: 各ノードの詳細メトリクス
  - CPU使用率、ロードアベレージ
  - メモリ使用量、スワップ
  - ディスクI/O、ネットワークI/O
  - 温度センサー（Raspberry Pi）

### Pod/コンテナ監視
- **Kubernetes / Compute Resources / Namespace (Pods)**: Namespace別Pod統計
- **Kubernetes / Compute Resources / Pod**: 個別Pod詳細

### ストレージ
- **Kubernetes / Persistent Volumes**: PV/PVC使用状況

### アプリケーション監視
- **ArgoCD**: アプリケーションデプロイ状況、同期ステータス
- **Traefik**: Ingressトラフィック、レスポンスタイム

## カスタムダッシュボード

### インポート方法

1. Grafana UIにログイン
2. 左メニュー → **Dashboards** → **Import**
3. Dashboard IDまたはJSON入力
4. データソース: **Prometheus** を選択

### 推奨ダッシュボード

公式コミュニティから追加できるダッシュボード例：

| Dashboard ID | 名前 | 用途 |
|-------------|------|------|
| 315 | Kubernetes Cluster Monitoring | クラスタ全体概要 |
| 1860 | Node Exporter Full | ノード詳細 |
| 7249 | Kubernetes Cluster | クラスタ状態 |
| 13332 | Kubernetes / API server | APIサーバー監視 |

インポート例：
```
Dashboard → Import → ID: 315 → Load → Select Prometheus → Import
```

## 自動プロビジョニングされたカスタムダッシュボード

以下のカスタムダッシュボードが自動的にインポートされます：

### クラスタ監視
- **Kubernetes Cluster Overview**: クラスタ全体の健全性とリソース使用状況
  - ノード数（Ready/NotReady）
  - クラスタ全体のCPU/メモリ使用率
  - Pod数（Total/Running）
  - トップリソース消費Pod

### ノード詳細
- **Kubernetes Node Details**: 各ノードの詳細メトリクス
  - CPU使用率とロードアベレージ
  - メモリ使用量（Used/Buffers/Cached/Free）
  - ディスク使用率とI/O
  - ネットワークトラフィック
  - 温度センサー（Raspberry Pi）
  - システムアップタイム

### Pod/コンテナ監視
- **Kubernetes Pod Monitoring**: Pod別のリソース監視
  - Pod別CPU/メモリ使用量
  - コンテナ再起動回数
  - Pod状態（Running/Pending/Failed）
  - リソースリクエスト vs 実使用量

### OOMキラー監視
- **Kubernetes OOM Killer Monitor**: メモリ不足の監視
  - OOMキラー発生回数（1時間/24時間）
  - OOMKilledされたPod一覧
  - メモリ圧迫状態のノード
  - コンテナメモリ使用率（リミット比）

### ネットワークトラフィック
- **Kubernetes Network Traffic**: ネットワーク統計
  - ノード別Ingress/Egressトラフィック
  - ネットワークエラー・ドロップ
  - Pod別ネットワーク使用量
  - Traefik Ingressメトリクス（リクエスト率、レスポンスコード）

### ストレージ
- **Kubernetes Storage**: PV/PVC監視
  - PV/PVC数と状態
  - PVC使用率詳細
  - ストレージ使用量トレンド
  - Inode使用状況

## カスタムPrometheusアラート

以下のカスタムアラートルールが自動設定されています：

### クラスタヘルス
- **NodeDown**: ノードがダウン（2分以上）
- **NodeNotReady**: ノードがNotReady状態（5分以上）

### リソース使用率
- **HighCPUUsage**: CPU使用率 > 80%（5分間）
- **CriticalCPUUsage**: CPU使用率 > 95%（3分間）
- **HighMemoryUsage**: メモリ使用率 > 85%（5分間）
- **CriticalMemoryUsage**: メモリ使用率 > 95%（2分間）

### ディスク・ストレージ
- **DiskSpaceLow**: ディスク使用率 > 85%（5分間）
- **DiskSpaceCritical**: ディスク使用率 > 95%（2分間）
- **PVCAlmostFull**: PVC使用率 > 80%（5分間）

### OOMキラー
- **OOMKillerActive**: OOMキラーが発動
- **PodOOMKilled**: PodがOOMで終了
- **ContainerMemoryNearLimit**: コンテナメモリがリミットの90%超（5分間）

### Pod健全性
- **PodCrashLooping**: Podが再起動ループ（15分間で複数回）
- **PodNotReady**: PodがReady状態でない（10分以上）

### ネットワーク
- **HighNetworkErrors**: ネットワークエラー率が高い（5分間）
- **HighNetworkDrops**: パケットドロップ率が高い（5分間）

アラートの確認：
```bash
# Prometheus UIでアラート確認
# Status → Rules → custom-rules
```


## メトリクスクエリ例

Prometheus UIまたはGrafanaで以下のクエリを実行できます：

### CPU使用率
```promql
# ノード別CPU使用率（%）
100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Pod別CPU使用率
sum(rate(container_cpu_usage_seconds_total{pod!=""}[5m])) by (pod, namespace)
```

### メモリ使用量
```promql
# ノード別メモリ使用率（%）
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Pod別メモリ使用量（GB）
sum(container_memory_working_set_bytes{pod!=""}) by (pod, namespace) / 1024 / 1024 / 1024
```

### ディスク使用率
```promql
# ルートパーティション使用率（%）
(1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100
```

### Pod数
```promql
# Namespace別Pod数
count(kube_pod_info) by (namespace)

# ステータス別Pod数
count(kube_pod_status_phase) by (phase)
```

### ArgoCD同期状態
```promql
# 同期エラーのあるアプリケーション数
count(argocd_app_info{sync_status!="Synced"})
```

## アラート設定

### デフォルトアラート

以下のアラートが自動設定されています：

| アラート名 | 条件 | 重要度 |
|----------|------|--------|
| NodeMemoryHighUsage | メモリ使用率 > 90% | warning |
| NodeDiskSpaceRunningFull | ディスク使用率 > 85% | warning |
| KubePodCrashLooping | Pod再起動ループ | critical |
| KubeDeploymentReplicasMismatch | レプリカ数不一致 | warning |

### カスタムアラート追加

PrometheusRule CRDを作成：

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: my-custom-alerts
  namespace: monitoring
spec:
  groups:
    - name: my-alerts
      interval: 30s
      rules:
        - alert: HighCPUUsage
          expr: 100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "High CPU usage on {{ $labels.instance }}"
            description: "CPU usage is above 80% (current: {{ $value }}%)"
```

適用：
```bash
kubectl apply -f my-custom-alerts.yaml
```

## ServiceMonitor追加

独自のアプリケーションメトリクスを収集するには、ServiceMonitorを作成：

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app-metrics
  namespace: my-app
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics
```

## データ保持期間

### デフォルト設定
- **Prometheus**: 15日間
- **Alertmanager**: 120時間（5日間）

### 変更方法

`k8s/infrastructure/argocd-apps/base/kube-prometheus-stack.yaml` を編集：

```yaml
prometheus:
  prometheusSpec:
    retention: 30d  # 30日間に変更
    retentionSize: "20GB"
```

## ストレージ管理

### 使用状況確認
```bash
# Prometheus PVC確認
kubectl get pvc -n monitoring

# ストレージ使用量
kubectl exec -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -- df -h /prometheus
```

### ストレージ拡張
```bash
# PVC編集（storageClassがリサイズ対応の場合）
kubectl edit pvc prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0 -n monitoring

# storage: 15Gi → 30Gi に変更
```

## トラブルシューティング

### Grafana にログインできない

```bash
# パスワードリセット
kubectl exec -n monitoring deploy/kube-prometheus-stack-grafana -- grafana-cli admin reset-admin-password newpassword

# Pod再起動
kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring
```

### Prometheus がメトリクスを収集しない

```bash
# Prometheus設定確認
kubectl get configmap -n monitoring prometheus-kube-prometheus-stack-prometheus-rulefiles-0 -o yaml

# ServiceMonitor確認
kubectl get servicemonitor -A

# Prometheusログ確認
kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -c prometheus
```

### メモリ不足エラー

Raspberry Piのメモリ制約がある場合、リソース制限を調整：

```yaml
# kube-prometheus-stack.yaml
prometheus:
  prometheusSpec:
    resources:
      limits:
        memory: 1Gi  # デフォルト2Giから削減
```

### ダッシュボードが表示されない

```bash
# Grafana Sidecar確認
kubectl logs -n monitoring deploy/kube-prometheus-stack-grafana -c grafana-sc-dashboard

# ConfigMap確認
kubectl get configmap -n monitoring | grep grafana
```

## パフォーマンス最適化

### Raspberry Pi向け設定

メモリとCPUを節約する設定：

```yaml
# Scrape間隔を延長（デフォルト30s → 60s）
prometheus:
  prometheusSpec:
    scrapeInterval: 60s
    evaluationInterval: 60s

# 保持期間を短縮
    retention: 7d
    retentionSize: "8GB"
```

### メトリクス収集を選別

不要なメトリクスを除外：

```yaml
prometheus:
  prometheusSpec:
    additionalScrapeConfigs:
      - job_name: 'kubernetes-pods'
        metric_relabel_configs:
          # 高カーディナリティメトリクスをドロップ
          - source_labels: [__name__]
            regex: 'container_network_.*'
            action: drop
```

## 参考リンク

- [Prometheus公式ドキュメント](https://prometheus.io/docs/)
- [Grafana公式ドキュメント](https://grafana.com/docs/)
- [kube-prometheus-stack GitHub](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [PromQL入門](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Grafanaダッシュボードライブラリ](https://grafana.com/grafana/dashboards/)

## まとめ

このドキュメントでは、kube-prometheus-stackを使った監視環境の使い方を説明しました。Grafanaダッシュボードで可視化し、Prometheusクエリで詳細分析を行い、カスタムアラートで問題を早期検知できます。

より詳しい情報は、上記の公式ドキュメントを参照してください。
