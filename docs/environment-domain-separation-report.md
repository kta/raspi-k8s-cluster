# 環境別ドメイン分離完了レポート

## ✅ 実装完了

Production環境とVagrant環境で異なるドメインを使用するように、**全ファイルを漏れなく修正**しました。

## 🌐 ドメイン設定

| 環境 | ドメイン | 例 | ClusterIssuer | 証明書タイプ |
|------|---------|-----|--------------|-------------|
| **Production** | `*.raspi.local` | `argocd.raspi.local` | `letsencrypt` | Let's Encrypt（公開CA） |
| **Vagrant** | `*.vagrant.local` | `argocd.vagrant.local` | `ca-issuer` | 自己署名CA（ローカル専用） |

## 📝 修正したファイル一覧

### 1. Kubernetes Manifests

#### ApplicationSet環境パラメータ
- ✅ `k8s/bootstrap/values/vagrant.yaml`
  - `domain: vagrant.local`
  - `argocd.hostname: argocd.vagrant.local`
  - `atlantis.hostname: atlantis.vagrant.local`
  - `certManager.email: admin@vagrant.local`

#### Ingress Overlays（Vagrant環境）
- ✅ `k8s/infrastructure/argocd/overlays/vagrant/kustomization.yaml`
  - ホスト名: `argocd.vagrant.local`
  - ClusterIssuer: `ca-issuer`

- ✅ `k8s/infrastructure/atlantis/overlays/vagrant/kustomization.yaml`
  - ホスト名: `atlantis.vagrant.local`
  - ClusterIssuer: `ca-issuer`

- ✅ `k8s/infrastructure/traefik/overlays/vagrant/kustomization.yaml`
  - ホスト名: `traefik.vagrant.local`
  - ClusterIssuer: `ca-issuer`

### 2. スクリプト

#### DNS設定スクリプト
- ✅ `scripts/setup_local_dns.sh`
  - Production: `*.raspi.local` → Ingress IP
  - Vagrant: `*.vagrant.local` → Ingress IP
  - 環境別設定ファイル: `raspi-k8s-${ENVIRONMENT}.conf`
  - 環境別resolver: `/etc/resolver/${DOMAIN}`

#### CA証明書生成スクリプト
- ✅ `scripts/generate_ca_cert.sh`
  - 第2引数で環境指定可能: `./generate_ca_cert.sh certs vagrant`
  - Production: `raspi.local Root CA`
  - Vagrant: `vagrant.local Root CA`

#### CA証明書信頼スクリプト
- ✅ `scripts/trust_ca_cert.sh`
  - 第2引数で環境指定可能: `./trust_ca_cert.sh certs/ca.crt vagrant`
  - 環境別CN名で検証
  - 環境別アクセスURL表示

### 3. Makefile

- ✅ `Makefile` - 環境変数`$(ENVIRONMENT)`を全ターゲットに伝播
  - `make generate-ca ENV=vagrant` → 環境別CA証明書生成
  - `make install-ca ENV=vagrant` → エラーメッセージも環境別
  - `make trust-ca ENV=vagrant` → 環境別CA信頼設定
  - `make setup-https ENV=vagrant` → 環境別URL表示
  - `make setup-local-dns ENV=vagrant` → 環境別DNS設定

### 4. ドキュメント

#### メインガイド
- ✅ `docs/guides/https-setup.md`
  - 環境別ドメイン表を追加
  - Vagrant例: `https://argocd.vagrant.local`
  - Production例: `https://argocd.raspi.local`
  - 全コマンド例で環境指定を明記

#### README
- ✅ `README.md`
  - サービスアクセス例を環境別に更新

#### ドキュメントインデックス
- ✅ `docs/README.md`
  - HTTPSセットアップガイドへのリンク追加済み

## 🚀 使い方

### Vagrant環境（開発）

```bash
# 1. dnsmasqインストール（初回のみ）
brew install dnsmasq

# 2. ローカルDNS設定
make setup-local-dns ENV=vagrant

# 3. HTTPSセットアップ（CA生成→インストール→信頼）
make setup-https ENV=vagrant

# 4. ブラウザ再起動

# 5. アクセス
open https://argocd.vagrant.local
open https://atlantis.vagrant.local
open https://traefik.vagrant.local
```

### Production環境（本番）

```bash
# 1. dnsmasqインストール（初回のみ）
brew install dnsmasq

# 2. ローカルDNS設定
make setup-local-dns ENV=production

# 3. Let's Encryptが自動的に証明書発行
# （CA証明書生成は不要）

# 4. アクセス
open https://argocd.raspi.local
open https://atlantis.raspi.local
open https://traefik.raspi.local
```

## ✅ テスト済み項目

- [x] **shellcheck通過** - 全スクリプト警告なし
- [x] **Makefile動作確認** - 全ターゲットが正しく表示
- [x] **Vagrant values検証** - `domain: vagrant.local`
- [x] **Ingress kustomization検証** - すべて`*.vagrant.local`
- [x] **ClusterIssuer設定確認** - `ca-issuer`適用済み
- [x] **Production values確認** - `domain: raspi.local`（変更なし）

## 🔍 変更の仕組み

### 環境自動切り替えフロー

```
1. Makefile ENV=vagrant
   ↓
2. ENVIRONMENT=vagrant
   ↓
3. スクリプトに環境を渡す
   ↓
4. 環境別処理
   - setup_local_dns.sh → DOMAIN=vagrant.local
   - generate_ca_cert.sh → DOMAIN=vagrant.local
   - trust_ca_cert.sh → CN_NAME=vagrant.local Root CA
   ↓
5. 環境別ファイル生成
   - /opt/homebrew/etc/dnsmasq.d/raspi-k8s-vagrant.conf
   - /etc/resolver/vagrant.local
   - certs/ca.crt (CN=vagrant.local Root CA)
```

### Kustomize Overlay構造

```
k8s/infrastructure/
├── argocd/
│   ├── base/
│   │   └── ingress.yaml          # argocd.raspi.local (デフォルト)
│   └── overlays/
│       ├── production/           # 変更なし（raspi.local使用）
│       └── vagrant/
│           └── kustomization.yaml # → argocd.vagrant.local
├── atlantis/
│   ├── base/
│   │   └── ingress.yaml          # atlantis.raspi.local (デフォルト)
│   └── overlays/
│       ├── production/           # 変更なし（raspi.local使用）
│       └── vagrant/
│           └── kustomization.yaml # → atlantis.vagrant.local
└── traefik/
    ├── base/
    │   └── middleware.yaml
    └── overlays/
        ├── production/           # 変更なし（raspi.local使用）
        └── vagrant/
            └── kustomization.yaml # → traefik.vagrant.local
```

## 📋 Makefile コマンド一覧

| コマンド | 説明 | 環境指定 |
|----------|------|---------|
| `make setup-local-dns ENV=vagrant` | dnsmasqでローカルDNS設定 | 必須 |
| `make generate-ca ENV=vagrant` | CA証明書生成 | 必須 |
| `make install-ca ENV=vagrant` | CA証明書をKubernetesにインストール | 推奨 |
| `make trust-ca ENV=vagrant` | CA証明書をシステムで信頼 | 必須 |
| `make setup-https ENV=vagrant` | HTTPS完全自動化 | 必須 |

## 🎯 次のステップ

### ユーザーが実行すべきこと

1. **dnsmasqインストール（初回のみ）:**
   ```bash
   brew install dnsmasq
   ```

2. **Vagrant環境でテスト:**
   ```bash
   # クラスタセットアップ
   make setup-all-vagrant ENV=vagrant
   
   # DNS設定
   make setup-local-dns ENV=vagrant
   
   # HTTPS設定
   make setup-https ENV=vagrant
   
   # アクセス確認
   open https://argocd.vagrant.local
   open https://atlantis.vagrant.local
   ```

3. **Production環境（必要に応じて）:**
   ```bash
   make setup-local-dns ENV=production
   open https://argocd.raspi.local
   ```

## 📚 関連ドキュメント

- **詳細ガイド**: `docs/guides/https-setup.md`
- **サービスアクセス**: `docs/guides/service-access.md`
- **トラブルシューティング**: `docs/guides/troubleshooting.md`

## 🔒 セキュリティ

- ✅ CA秘密鍵は `.gitignore` で保護
- ✅ Vagrant環境のみで自己署名CA使用
- ✅ Production環境はLet's Encrypt継続
- ✅ 環境別に完全分離

## 🎉 完了

すべてのファイルが環境別ドメインに対応し、**漏れなく修正**完了しました！

---

**実装日:** 2026-01-20  
**対応環境:** Production (`*.raspi.local`) / Vagrant (`*.vagrant.local`)  
**状態:** ✅ Production Ready
