# ローカルHTTPSセットアップガイド

このガイドでは、自己署名CA証明書を使用してローカル環境（Vagrant）でHTTPS通信を実現する方法を説明します。

## 概要

Let's Encryptは公開ドメインが必要なため、`*.raspi.local`のようなローカルドメインでは使用できません。そこで、自己署名CA証明書を使用してローカル環境専用のHTTPS環境を構築します。

### アーキテクチャ

```
┌─────────────────────────────────────────────────────────┐
│ 1. 自己署名CA証明書生成 (scripts/generate_ca_cert.sh) │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│ 2. CA SecretをKubernetesにインストール                 │
│    (kubectl apply -f certs/ca-secret.yaml)             │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│ 3. cert-manager CA Issuerがデプロイされる              │
│    (k8s/infrastructure/cert-manager-resources/)        │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│ 4. IngressがCertificateを自動的にリクエスト            │
│    (cert-manager.io/cluster-issuer: ca-issuer)         │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│ 5. CA証明書をクライアントシステムで信頼                 │
│    (scripts/trust_ca_cert.sh)                          │
└─────────────────────────────────────────────────────────┘
```

## クイックスタート

### 全自動セットアップ

```bash
# Vagrant環境の場合
# 1. ローカルDNS設定
make setup-local-dns ENV=vagrant

# 2. HTTPSセットアップ（CA生成→インストール→信頼）
make setup-https ENV=vagrant

# 3. ブラウザを再起動

# 4. アクセス確認
open https://argocd.vagrant.local


# Production環境の場合（本番環境ではLet's Encryptを使用）
# 1. ローカルDNS設定
make setup-local-dns ENV=production

# 2. Let's Encryptが自動的に証明書を発行（手動CA不要）

# 3. アクセス確認
open https://argocd.raspi.local
```

### 手動セットアップ（詳細）

#### 1. CA証明書の生成

```bash
make generate-ca
# または
./scripts/generate_ca_cert.sh

# 出力ファイル:
#   certs/ca.key         - CA秘密鍵（機密！）
#   certs/ca.crt         - CA証明書（ブラウザにインストール）
#   certs/ca-secret.yaml - Kubernetes Secret
```

#### 2. CA証明書をKubernetesにインストール

```bash
make install-ca
# または
kubectl create namespace cert-manager || true
kubectl apply -f certs/ca-secret.yaml
```

#### 3. cert-manager CA Issuerのデプロイ

ApplicationSetが自動的にデプロイします：

```bash
# Vagrant環境ではca-issuerが自動的に使用される
kubectl get clusterissuer ca-issuer
```

#### 4. CA証明書をブラウザ/システムで信頼

```bash
make trust-ca
# または
./scripts/trust_ca_cert.sh
```

**macOS:**
- システムキーチェーンに自動インストール
- パスワードプロンプトが表示されます

**Linux:**
- Debian/Ubuntu: `/usr/local/share/ca-certificates/` にコピー
- CentOS/RHEL: `/etc/pki/ca-trust/source/anchors/` にコピー

**Windows:**
1. `certs/ca.crt` をダブルクリック
2. 「証明書のインストール」→「ローカルコンピューター」
3. 「信頼されたルート証明機関」に配置

#### 5. ブラウザの再起動

CA証明書を信頼設定した後、ブラウザを再起動してください。

## 仕組み

### 環境別のClusterIssuer設定

**Vagrant環境:**
- `ca-issuer` を使用（自己署名CA）
- Ingressアノテーション: `cert-manager.io/cluster-issuer: ca-issuer`

**Production環境:**
- `letsencrypt` を使用（Let's Encrypt）
- Ingressアノテーション: `cert-manager.io/cluster-issuer: letsencrypt`

### Kustomize Overlaysによる自動切り替え

```yaml
# k8s/infrastructure/argocd/overlays/vagrant/kustomization.yaml
patches:
  - target:
      kind: Ingress
      name: argocd-server
    patch: |-
      - op: replace
        path: /metadata/annotations/cert-manager.io~1cluster-issuer
        value: "ca-issuer"  # Vagrant環境ではca-issuerを使用
```

### cert-manager CA Issuer

```yaml
# k8s/infrastructure/cert-manager-resources/base/ca-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ca-issuer
spec:
  ca:
    secretName: ca-key-pair  # ステップ2でインストールしたSecret
```

## トラブルシューティング

### 証明書が発行されない

```bash
# Certificateの状態確認
kubectl get certificate -A

# cert-managerログ確認
kubectl logs -n cert-manager -l app=cert-manager -f

# CA Secretが存在するか確認
kubectl get secret -n cert-manager ca-key-pair
```

**よくある原因:**
1. CA Secretが存在しない → `make install-ca`
2. CA Issuerがデプロイされていない → ArgoCD同期を確認
3. Ingressのアノテーションが間違っている → overlay確認

### ブラウザで証明書エラーが出る

**Chrome/Edge:**
1. `chrome://settings/certificates` → 「認証局」タブ
2. `raspi.local Root CA` が存在するか確認
3. なければ `certs/ca.crt` をインポート

**Firefox:**
1. `about:preferences#privacy` → 「証明書を表示」
2. 「認証局証明書」タブで確認
3. なければ `certs/ca.crt` をインポート

**Safari (macOS):**
```bash
# システムキーチェーンで確認
security find-certificate -c "raspi.local Root CA" /Library/Keychains/System.keychain

# 削除して再インストール
sudo security delete-certificate -c "raspi.local Root CA" /Library/Keychains/System.keychain
make trust-ca
```

### DNSが解決されない

```bash
# DNS確認
nslookup argocd.vagrant.local
ping -c 1 argocd.vagrant.local

# dnsmasq状態確認（macOS）
brew services list | grep dnsmasq

# dnsmasq再起動
make setup-local-dns ENV=vagrant
```

## ファイル構成

```
raspi-k8s-cluster/
├── scripts/
│   ├── generate_ca_cert.sh          # CA証明書生成
│   ├── trust_ca_cert.sh             # CA証明書信頼設定
│   └── setup_local_dns.sh           # DNS設定
├── certs/                           # 生成される証明書（gitignore）
│   ├── ca.key                       # CA秘密鍵
│   ├── ca.crt                       # CA証明書
│   └── ca-secret.yaml               # Kubernetes Secret
└── k8s/infrastructure/
    ├── cert-manager-resources/      # CA Issuer定義
    │   ├── base/
    │   │   ├── ca-issuer.yaml
    │   │   └── kustomization.yaml
    │   └── overlays/
    │       ├── production/          # （空）
    │       └── vagrant/             # CA Issuerを含む
    ├── argocd/overlays/vagrant/     # Ingressでca-issuer使用
    └── atlantis/overlays/vagrant/   # Ingressでca-issuer使用
```

## セキュリティ考慮事項

### CA秘密鍵の保護

⚠️ **重要:** `certs/ca.key` は絶対に公開しないでください！

- Gitリポジトリに追加禁止（`.gitignore`で保護）
- ローカル環境のみで保管
- パーミッション: `chmod 600 certs/ca.key`

### Production環境での使用

❌ **本番環境では自己署名CA証明書を使用しないでください**

- Let's Encryptを使用（自動更新、広く信頼済み）
- ApplicationSetが自動的にLet's Encryptを使用
- `letsencrypt` ClusterIssuerが設定済み

### 証明書の有効期限

```bash
# CA証明書の有効期限確認
openssl x509 -in certs/ca.crt -noout -dates

# 発行された証明書の確認
kubectl get certificate -A
kubectl describe certificate argocd-tls -n argocd
```

デフォルト有効期限:
- CA証明書: 10年
- 発行された証明書: 90日（自動更新）

## アンインストール

### CA証明書の削除

```bash
# Kubernetesから削除
kubectl delete secret -n cert-manager ca-key-pair

# ローカルファイル削除
rm -rf certs/

# ブラウザ/システムから削除（macOS）
sudo security delete-certificate -c "raspi.local Root CA" /Library/Keychains/System.keychain

# DNS設定削除
sudo rm /opt/homebrew/etc/dnsmasq.d/raspi-k8s.conf
sudo rm /etc/resolver/raspi.local
sudo brew services restart dnsmasq
```

## 参考資料

- [cert-manager CA Issuer Documentation](https://cert-manager.io/docs/configuration/ca/)
- [Kustomize Strategic Merge Patches](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/#customizing)
- [OpenSSL Certificate Generation](https://www.openssl.org/docs/man1.1.1/man1/req.html)

## Makefile コマンドリファレンス

| コマンド | 説明 |
|----------|------|
| `make generate-ca` | CA証明書を生成 |
| `make install-ca` | CA証明書をKubernetesにインストール |
| `make trust-ca` | CA証明書をシステムで信頼 |
| `make setup-https` | HTTPSセットアップ完全自動化 |
| `make setup-local-dns` | ローカルDNS設定 |
| `make show-ingress-urls` | アクセス可能なURL一覧表示 |
