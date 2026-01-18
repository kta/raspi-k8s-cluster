# `/etc/hosts` 不要のサービスアクセス方法

## 🎯 目的

`/etc/hosts` を編集せずに、環境に応じて ArgoCD、Atlantis、Traefik にアクセスできるようにする。

---

## 🚀 方法一覧

| 方法 | 設定の手間 | 環境切り替え | インターネット | 本番に近い | コマンド |
|------|-----------|-------------|--------------|-----------|---------|
| **1. port-forward** | ★☆☆ | 不要 | 不要 | △ | `make port-forward-all` |
| **2. nip.io** | ★☆☆ | 自動 | 必要 | ○ | `make show-ingress-urls` |
| **3. dnsmasq** | ★★☆ | 自動 | 不要 | ◎ | `make setup-local-dns` |

---

## 方法1: kubectl port-forward（推奨：開発環境）

### 📝 概要
ローカルホストに自動的にポートフォワード。最もシンプルで確実な方法。

### ✅ メリット
- 設定不要（すぐに使える）
- `/etc/hosts` 不要
- セキュア（外部公開なし）
- 環境切り替え不要

### ❌ デメリット
- ターミナルを開いたまま維持
- 本番に近い環境ではない

### 🚀 使い方

```bash
# 個別にポートフォワード
make port-forward-argocd    # http://localhost:8080
make port-forward-atlantis  # http://localhost:4141
make port-forward-traefik   # http://localhost:9000

# 全サービスを一度にポートフォワード
make port-forward-all

# 停止: Ctrl+C
```

### 📋 アクセス先

| サービス | URL | 初期認証情報 |
|---------|-----|-------------|
| ArgoCD | http://localhost:8080 | `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' \| base64 -d` |
| Atlantis | http://localhost:4141 | webhook認証 |
| Traefik | http://localhost:9000 | なし（Dashboard） |

---

## 方法2: nip.io / sslip.io（推奨：インターネット接続あり）

### 📝 概要
IPアドレスをドメイン名に埋め込むワイルドカードDNSサービス。

**nip.io の仕組み:**
```
argocd-192-168-1-200.nip.io  → 192.168.1.200 に自動解決
```

**sslip.io の仕組み:**
```
argocd.192.168.1.200.sslip.io → 192.168.1.200 に自動解決
```

### ✅ メリット
- `/etc/hosts` 編集不要
- 環境変数から自動的にURLを生成可能
- 追加のソフトウェア不要
- TLS証明書も取得可能（Let's Encrypt）

### ❌ デメリット
- インターネット接続が必要（DNSクエリ）
- URLが少し長くなる

### 🚀 使い方

```bash
# URLを生成して表示
make show-ingress-urls ENV=production

# 出力例:
# ✨ nip.io を使った URL:
#   🔹 ArgoCD:   http://argocd-192-168-1-200.nip.io
#   🔹 Atlantis: http://atlantis-192-168-1-200.nip.io
#   🔹 Traefik:  http://traefik-192-168-1-200.nip.io
#
# ✨ sslip.io を使った URL:
#   🔹 ArgoCD:   http://argocd.192.168.1.200.sslip.io
#   🔹 Atlantis: http://atlantis.192.168.1.200.sslip.io
#   🔹 Traefik:  http://traefik.192.168.1.200.sslip.io
```

### 📋 Ingress設定例

nip.io を使う場合、Ingressマニフェストのホスト名を変更：

```yaml
# k8s/infra/argocd/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-ingress
  namespace: argocd
spec:
  rules:
  - host: argocd-192-168-1-200.nip.io  # production
    # または
    # host: argocd-192-168-56-200.nip.io  # vagrant
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 443
```

### 💡 環境変数からの自動生成

将来的には、Kustomize overlays で環境別にホスト名を自動生成可能：

```yaml
# overlays/production/ingress-patch.yaml
- op: replace
  path: /spec/rules/0/host
  value: argocd-192-168-1-200.nip.io
```

---

## 方法3: dnsmasq（推奨：本番に近い環境）

### 📝 概要
環境変数から自動的にローカルDNSを設定。最も本番に近い環境。

### ✅ メリット
- 本番と同じ `.local` ドメインを使用
- 環境変数から自動設定
- TLS証明書の検証も可能
- 複数サービスに同時アクセス可能
- インターネット接続不要

### ❌ デメリット
- 初回セットアップが必要
- macOS の場合、追加の設定が必要
- sudo 権限が必要

### 🚀 使い方

#### 1. dnsmasq をインストール

```bash
# macOS
brew install dnsmasq

# Linux（Debian/Ubuntu）
sudo apt-get install dnsmasq

# Linux（CentOS/RHEL）
sudo yum install dnsmasq
```

#### 2. 自動設定スクリプトを実行

```bash
# Production環境
make setup-local-dns ENV=production

# Vagrant環境
make setup-local-dns ENV=vagrant

# 出力例:
# 📋 環境: production
# 📍 Ingress IP: 192.168.1.200
# 
# 🍎 macOS を検出しました
# 📝 dnsmasq 設定ファイルを作成中...
# ✅ 設定ファイルを作成しました
# 🔄 dnsmasq を再起動中...
# ✅ dnsmasq を再起動しました
# ✅ macOS resolver 設定を作成しました
# ✅ DNS キャッシュをクリアしました
# 
# ========================================
# ✅ ローカルDNS設定が完了しました！
# 
# 以下のURLでアクセス可能になりました:
#   🔹 http://argocd.local
#   🔹 http://atlantis.local
#   🔹 http://traefik.local
```

#### 3. 動作確認

```bash
# DNS解決を確認
nslookup argocd.local
# Server:		127.0.0.1
# Address:	127.0.0.1#53
# 
# Name:	argocd.local
# Address: 192.168.1.200

# 疎通確認
ping -c 1 argocd.local

# ブラウザでアクセス
open http://argocd.local
```

#### 4. 削除方法

```bash
# macOS
sudo rm /opt/homebrew/etc/dnsmasq.d/raspi-k8s.conf
sudo rm /etc/resolver/local
sudo brew services restart dnsmasq
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder

# Linux
sudo rm /etc/dnsmasq.d/raspi-k8s.conf
sudo systemctl restart dnsmasq
```

---

## 🎯 推奨アプローチ

### 開発環境（個人開発）
**方法1: port-forward**
```bash
make port-forward-all
```

理由:
- 設定不要で即座に使える
- 環境を汚さない
- デバッグしやすい

### 開発環境（チーム開発）
**方法3: dnsmasq**
```bash
make setup-local-dns ENV=production
```

理由:
- 本番に近い環境でテスト可能
- URLが短くて覚えやすい
- チーム全員が同じURLを使える

### 実機環境（外部公開あり）
**方法2: nip.io + Let's Encrypt**

理由:
- TLS証明書を自動取得可能
- `/etc/hosts` 編集不要
- 外部からもアクセス可能

---

## 📋 比較表（詳細）

| 項目 | port-forward | nip.io | dnsmasq |
|------|-------------|--------|---------|
| 設定時間 | 0分 | 5分 | 10分 |
| `/etc/hosts` 編集 | 不要 | 不要 | 不要 |
| インターネット接続 | 不要 | 必要 | 不要 |
| sudo 権限 | 不要 | 不要 | 必要 |
| URL | `localhost:8080` | `argocd-192-168-1-200.nip.io` | `argocd.local` |
| TLS証明書 | 不可 | 可能 | 可能（要設定） |
| 複数サービス同時 | 可能 | 可能 | 可能 |
| 外部公開 | 不可 | 可能 | 不可 |
| 環境切り替え | 不要 | 自動 | 自動 |
| 保守性 | ◎ | ○ | △ |

---

## 🛠️ トラブルシューティング

### port-forward が失敗する

```bash
# Podが起動しているか確認
kubectl get pods -n argocd
kubectl get pods -n atlantis
kubectl get pods -n traefik

# サービスが存在するか確認
kubectl get svc -n argocd
kubectl get svc -n atlantis
kubectl get svc -n traefik

# ログを確認
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
```

### nip.io が解決できない

```bash
# DNSクエリを確認
nslookup argocd-192-168-1-200.nip.io

# インターネット接続を確認
ping -c 1 nip.io

# 代わりに sslip.io を試す
nslookup argocd.192.168.1.200.sslip.io
```

### dnsmasq が起動しない（macOS）

```bash
# dnsmasq の状態を確認
brew services list | grep dnsmasq

# ログを確認
tail -f /opt/homebrew/var/log/dnsmasq.log

# 設定ファイルの構文チェック
dnsmasq --test

# 手動で起動
sudo dnsmasq --keep-in-foreground --log-queries
```

### macOS で .local が解決されない

```bash
# resolver 設定を確認
ls -la /etc/resolver/

# mDNSResponder を再起動
sudo killall -HUP mDNSResponder

# scutil で DNS 設定を確認
scutil --dns | grep local

# システムの DNS 設定を確認
networksetup -getdnsservers Wi-Fi
```

---

## 💡 まとめ

**3つの方法すべてを実装したので、好きな方法を選べます！**

- 🚀 **すぐに試したい** → `make port-forward-all`
- 🌐 **インターネット接続あり** → `make show-ingress-urls`
- 🏠 **本番に近い環境** → `make setup-local-dns`

どの方法も `/etc/hosts` の手動編集は不要です！✨

