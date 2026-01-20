# ローカルHTTPSセットアップ完了レポート

## 🎉 実装完了

`argocd.raspi.local` などのローカルドメインでHTTPS通信を実現する完全な実装が完了しました！

## 📦 実装内容

### 1. 自己署名CA証明書生成システム

**新規作成:**
- `scripts/generate_ca_cert.sh` - CA証明書の自動生成
  - 10年間有効なCA証明書作成
  - Kubernetes Secret YAML自動生成
  - 詳細な手順ガイド付き

**使い方:**
```bash
make generate-ca
# または
./scripts/generate_ca_cert.sh

# 出力:
#   certs/ca.key         - CA秘密鍵（gitignore済み）
#   certs/ca.crt         - CA証明書
#   certs/ca-secret.yaml - Kubernetes Secret
```

### 2. cert-manager CA Issuer統合

**新規作成:**
```
k8s/infrastructure/cert-manager-resources/
├── base/
│   ├── ca-issuer.yaml           # CA ClusterIssuer定義
│   └── kustomization.yaml
└── overlays/
    ├── production/              # （空）Let's Encryptのみ
    │   └── kustomization.yaml
    └── vagrant/                 # CA Issuer有効
        └── kustomization.yaml
```

**機能:**
- Vagrant環境では `ca-issuer` を自動使用
- Production環境では `letsencrypt` を継続使用
- Ingressアノテーションが環境別に自動切り替え

**修正:**
- `k8s/infrastructure/argocd-apps/base/cert-manager-resources.yaml`
  - パスを `cert-manager-resources/` に修正
- `k8s/infrastructure/argocd-apps/overlays/*/kustomization.yaml`
  - 両環境のパスを更新

### 3. Ingress TLS設定の環境別自動切り替え

**修正:**
- `k8s/infrastructure/argocd/overlays/vagrant/kustomization.yaml`
  - `cert-manager.io/cluster-issuer: ca-issuer` パッチ追加
- `k8s/infrastructure/atlantis/overlays/vagrant/kustomization.yaml`
  - 同上

**仕組み:**
```yaml
# Vagrant環境では自動的にca-issuerを使用
patches:
  - target:
      kind: Ingress
      name: argocd-server
    patch: |-
      - op: replace
        path: /metadata/annotations/cert-manager.io~1cluster-issuer
        value: "ca-issuer"
```

### 4. CA証明書信頼設定スクリプト

**新規作成:**
- `scripts/trust_ca_cert.sh` - CA証明書をシステムで信頼

**対応プラットフォーム:**
- ✅ macOS (Keychain自動登録)
- ✅ Linux (Debian/Ubuntu, CentOS/RHEL)
- ✅ Windows (手動手順ガイド)
- ✅ Chrome/Firefox (手動手順ガイド)

**使い方:**
```bash
make trust-ca
# または
./scripts/trust_ca_cert.sh
```

### 5. ローカルDNS設定スクリプト更新

**更新:**
- `scripts/setup_local_dns.sh` - `*.raspi.local` ドメイン対応

**変更点:**
- `address=/raspi.local/$INGRESS_IP`
- `address=/.raspi.local/$INGRESS_IP`
- HTTPS URL表示
- CA証明書設定ガイド追加

### 6. Makefile統合

**新規ターゲット:**
```bash
make generate-ca      # CA証明書生成
make install-ca       # CA証明書をKubernetesにインストール
make trust-ca         # CA証明書をシステムで信頼
make setup-https      # 完全自動化（全ステップ実行）
make setup-local-dns  # DNS設定（既存を更新）
```

### 7. 包括的ドキュメント

**新規作成:**
- `docs/guides/https-setup.md` - 完全なHTTPSセットアップガイド
  - クイックスタート
  - 詳細な仕組み解説
  - トラブルシューティング
  - セキュリティ考慮事項
  - Makefileコマンドリファレンス

**更新:**
- `docs/README.md` - HTTPSガイドへのリンク追加

## 🚀 使い方（クイックスタート）

### Vagrant環境での完全セットアップ

```bash
# 1. ローカルDNS設定
make setup-local-dns ENV=vagrant

# 2. HTTPSセットアップ（完全自動化）
make setup-https ENV=vagrant

# 3. ブラウザ再起動

# 4. アクセス確認
open https://argocd.raspi.local
open https://atlantis.raspi.local
```

### ステップバイステップ（詳細制御）

```bash
# 1. CA証明書生成
make generate-ca

# 2. CA証明書をKubernetesにインストール
make install-ca

# 3. ArgoCD同期（CA Issuerデプロイ）
# ApplicationSetが自動的に処理

# 4. 証明書発行確認
kubectl get certificate -A
kubectl get clusterissuer ca-issuer

# 5. CA証明書をシステムで信頼
make trust-ca

# 6. DNS設定
make setup-local-dns ENV=vagrant

# 7. ブラウザ再起動してアクセス
open https://argocd.raspi.local
```

## 🔍 技術的な仕組み

### フロー図

```
┌─────────────────────────────────────────────┐
│ 1. CA証明書生成 (make generate-ca)         │
│    → certs/ca.crt, ca.key, ca-secret.yaml  │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│ 2. Secret適用 (make install-ca)            │
│    → kubectl apply -f certs/ca-secret.yaml │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│ 3. CA Issuerデプロイ (ArgoCD自動)          │
│    → ApplicationSet → ca-issuer            │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│ 4. Ingress作成 → Certificate自動発行       │
│    cert-manager.io/cluster-issuer: ca-issuer│
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│ 5. クライアント信頼 (make trust-ca)        │
│    → システムキーチェーン/トラストストア   │
└─────────────────────────────────────────────┘
```

### 環境別の動作

| 環境 | ClusterIssuer | 証明書 | DNSドメイン |
|------|--------------|--------|------------|
| **vagrant** | `ca-issuer` | 自己署名CA | `*.raspi.local` |
| **production** | `letsencrypt` | Let's Encrypt | 公開ドメイン |

### Kustomize Overlaysによる自動切り替え

```yaml
# Vagrant環境 (k8s/infrastructure/argocd/overlays/vagrant/)
patches:
  - target:
      kind: Ingress
      name: argocd-server
    patch: |-
      - op: replace
        path: /metadata/annotations/cert-manager.io~1cluster-issuer
        value: "ca-issuer"  # ← Vagrant専用

# Production環境
# パッチなし → base のまま letsencrypt を使用
```

## 📁 新規ファイル一覧

```
raspi-k8s-cluster/
├── scripts/
│   ├── generate_ca_cert.sh          # ✨ 新規
│   ├── trust_ca_cert.sh             # ✨ 新規
│   └── setup_local_dns.sh           # 🔄 更新
├── certs/                           # ✨ 新規（gitignore）
│   ├── ca.key
│   ├── ca.crt
│   └── ca-secret.yaml
├── k8s/infrastructure/
│   ├── cert-manager-resources/      # ✨ 新規
│   │   ├── base/
│   │   │   ├── ca-issuer.yaml
│   │   │   └── kustomization.yaml
│   │   └── overlays/
│   │       ├── production/
│   │       └── vagrant/
│   ├── argocd-apps/
│   │   ├── base/
│   │   │   └── cert-manager-resources.yaml  # 🔄 パス修正
│   │   └── overlays/
│   │       ├── production/kustomization.yaml  # 🔄 パス修正
│   │       └── vagrant/kustomization.yaml     # 🔄 パス修正
│   ├── argocd/overlays/vagrant/
│   │   └── kustomization.yaml       # 🔄 ca-issuerパッチ追加
│   └── atlantis/overlays/vagrant/
│       └── kustomization.yaml       # 🔄 ca-issuerパッチ追加
├── docs/guides/
│   └── https-setup.md               # ✨ 新規
├── docs/README.md                   # 🔄 更新
└── Makefile                         # 🔄 5つの新ターゲット追加
```

## ✅ テスト済み項目

- [x] shellcheck - 全スクリプト警告なし（SC2034除く）
- [x] Makefile - 新ターゲットが正しく表示
- [x] Kustomize - overlaysが正しくパッチ適用
- [x] ファイル構造 - すべてのパスが一貫性保持

## 🔒 セキュリティ考慮事項

### ✅ 実装済み

1. **CA秘密鍵の保護**
   - `certs/` ディレクトリは `.gitignore` で保護
   - スクリプトで権限警告表示

2. **環境分離**
   - Vagrant環境のみで自己署名CA使用
   - Production環境はLet's Encrypt継続

3. **証明書有効期限**
   - CA証明書: 10年
   - 発行証明書: 90日（cert-manager自動更新）

### ⚠️ 注意事項

- **CA秘密鍵(`certs/ca.key`)は絶対に公開しないこと**
- **Production環境で自己署名CA証明書を使用しないこと**
- **ローカル開発環境専用**

## 📚 ドキュメント

- **メインガイド:** `docs/guides/https-setup.md`
- **クイックスタート:** セクションあり
- **トラブルシューティング:** 詳細あり
- **Makefile統合:** `make help` で確認可能

## 🎯 次のステップ

ユーザーが実行すべきこと：

1. **Vagrant環境でテスト:**
   ```bash
   make setup-all-vagrant ENV=vagrant
   make setup-local-dns ENV=vagrant
   make setup-https ENV=vagrant
   open https://argocd.raspi.local
   ```

2. **ドキュメント確認:**
   ```bash
   open docs/guides/https-setup.md
   ```

3. **Production環境では使用しない:**
   - Production環境はLet's Encryptのまま
   - 自動的に環境別に切り替わる

## 🚨 既知の制限事項

1. **Let's EncryptはローカルドメインNG:**
   - `*.raspi.local` では使えない（仕様）
   - 自己署名CA証明書が必須

2. **ブラウザ再起動必須:**
   - CA証明書信頼後は必ずブラウザ再起動

3. **dnsmasq必須:**
   - macOS: `brew install dnsmasq`
   - Linux: `apt-get install dnsmasq` または `yum install dnsmasq`

## 🎓 学習リソース

実装で使用した技術：

- [cert-manager CA Issuer](https://cert-manager.io/docs/configuration/ca/)
- [Kustomize Patches](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/)
- [OpenSSL CA証明書](https://www.openssl.org/docs/man1.1.1/man1/req.html)
- [dnsmasq設定](https://thekelleys.org.uk/dnsmasq/doc.html)

---

**実装完了日:** 2026-01-20  
**実装者:** Claude Code  
**目的:** ローカル環境でのHTTPS通信実現  
**状態:** ✅ Production Ready (Vagrant環境限定)
