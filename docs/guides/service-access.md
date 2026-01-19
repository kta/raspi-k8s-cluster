# サービスアクセスガイド

デプロイしたサービス（ArgoCD、Atlantis、Traefik）に `/etc/hosts` を編集せずにアクセスする方法を説明します。

## 🎯 3つのアクセス方法

| 方法 | 設定難度 | インターネット | 本番に近い | 推奨用途 |
|------|---------|--------------|-----------|---------|
| **1. Port-forward** | ★☆☆ | 不要 | △ | 個人開発 |
| **2. nip.io** | ★☆☆ | 必要 | ○ | チーム開発 |
| **3. dnsmasq** | ★★☆ | 不要 | ◎ | 本番テスト |

---

## 方法1: kubectl port-forward（最も簡単）

### 概要
ローカルホストにポートフォワード。設定不要で即座に使える。

### 使い方

```bash
# 全サービスを一度にポートフォワード
make port-forward-all

# または個別に
make port-forward-argocd    # http://localhost:8080
make port-forward-atlantis  # http://localhost:4141
make port-forward-traefik   # http://localhost:9000
```

### アクセス先

| サービス | URL | 認証情報 |
|---------|-----|---------|
| ArgoCD | http://localhost:8080 | `admin` / [パスワード取得](#argocDパスワード取得) |
| Atlantis | http://localhost:4141 | webhook認証 |
| Traefik | http://localhost:9000 | なし（Dashboard） |

#### ArgoCDパスワード取得
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

### メリット・デメリット

✅ **メリット**
- 設定不要（すぐ使える）
- `/etc/hosts` 不要
- セキュア（外部公開なし）

❌ **デメリット**
- ターミナルを開いたまま維持
- 複数サービス同時アクセスには複数ターミナル必要

---

## 方法2: nip.io / sslip.io（DNS不要）

### 概要
IPアドレスをドメイン名に埋め込むワイルドカードDNSサービス。

**仕組み:**
```
argocd-192-168-1-200.nip.io      → 192.168.1.200 に自動解決
argocd.192.168.1.200.sslip.io    → 192.168.1.200 に自動解決
```

### 使い方

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

### 環境別URL

#### production環境
```bash
make show-ingress-urls ENV=production
# 192.168.1.200 を使ったURL
```

#### vagrant環境
```bash
make show-ingress-urls ENV=vagrant
# 192.168.56.200 を使ったURL
```

### Ingressマニフェストの設定

nip.ioを使う場合、Ingressのhostを以下のように設定：

```yaml
# k8s/infrastructure/argocd/ingress.yaml
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

### メリット・デメリット

✅ **メリット**
- `/etc/hosts` 編集不要
- 環境変数から自動URL生成
- TLS証明書も取得可能（Let's Encrypt）
- チーム全員が同じURLを使える

❌ **デメリット**
- インターネット接続が必要（DNSクエリ）
- URLが少し長くなる

---

## 方法3: dnsmasq（最も本番に近い）

### 概要
環境変数から自動的にローカルDNSを設定。本番環境に最も近い。

### 使い方

#### 1. dnsmasqをインストール

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
# production環境
make setup-local-dns ENV=production

# vagrant環境
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

### メリット・デメリット

✅ **メリット**
- 本番と同じ `.local` ドメインを使用
- 環境変数から自動設定
- TLS証明書の検証も可能
- 複数サービスに同時アクセス可能
- インターネット接続不要

❌ **デメリット**
- 初回セットアップが必要
- sudo権限が必要
- macOSの場合、追加の設定が必要

---

## 🎯 推奨アプローチ

### 個人開発（すぐ試したい）
**→ 方法1: port-forward**
```bash
make port-forward-all
```
- 設定不要で即座に使える
- 環境を汚さない
- デバッグしやすい

### チーム開発（共有URL必要）
**→ 方法2: nip.io**
```bash
make show-ingress-urls ENV=production
```
- URLをチームで共有できる
- `/etc/hosts` 編集不要
- 外部からもアクセス可能

### 本番テスト（本番に近い環境）
**→ 方法3: dnsmasq**
```bash
make setup-local-dns ENV=production
```
- 本番と同じドメイン形式
- TLS証明書のテストも可能
- インターネット接続不要

---

## 🛠️ トラブルシューティング

### port-forwardが失敗する

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

### nip.ioが解決できない

```bash
# DNSクエリを確認
nslookup argocd-192-168-1-200.nip.io

# インターネット接続を確認
ping -c 1 nip.io

# 代わりに sslip.io を試す
nslookup argocd.192.168.1.200.sslip.io
```

### dnsmasqが起動しない（macOS）

```bash
# dnsmasqの状態を確認
brew services list | grep dnsmasq

# ログを確認
tail -f /opt/homebrew/var/log/dnsmasq.log

# 設定ファイルの構文チェック
dnsmasq --test

# 手動で起動
sudo dnsmasq --keep-in-foreground --log-queries
```

### macOSで.localが解決されない

```bash
# resolver設定を確認
ls -la /etc/resolver/

# mDNSResponderを再起動
sudo killall -HUP mDNSResponder

# scutilでDNS設定を確認
scutil --dns | grep local

# システムのDNS設定を確認
networksetup -getdnsservers Wi-Fi
```

### LoadBalancer IPが割り当てられない

```bash
# MetalLB Podの状態確認
kubectl get pods -n metallb-system

# MetalLB ログ確認
kubectl logs -n metallb-system -l app=metallb

# IPAddressPool確認
kubectl get ipaddresspool -n metallb-system -o yaml

# LoadBalancer Service確認
kubectl get svc -A --field-selector spec.type=LoadBalancer
```

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

## 📚 関連ドキュメント

- [クイックスタート](./quickstart.md) - 基本的なセットアップ手順
- [IP管理](./ip-management.md) - 環境別IP設定の詳細
- [トラブルシューティング](./troubleshooting.md) - よくある問題と解決策

---

## 💡 まとめ

**3つの方法すべてが利用可能です！**

- 🚀 **すぐに試したい** → `make port-forward-all`
- 🌐 **URLを共有したい** → `make show-ingress-urls`
- 🏠 **本番に近い環境** → `make setup-local-dns`

どの方法も `/etc/hosts` の手動編集は不要です！✨
