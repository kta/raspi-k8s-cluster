# ドキュメント

Raspberry Pi Kubernetesクラスタプロジェクトのドキュメント集です。

## 📚 ガイド

初めての方はここから：

### [🚀 クイックスタート](./guides/quickstart.md)
最短でクラスタをセットアップする手順。実機30分、Vagrant15分。

### [🌐 環境別IP管理](./guides/ip-management.md)
production/vagrant環境で異なるIPアドレスを自動管理する仕組み。

### [🔗 サービスアクセス](./guides/service-access.md)
ArgoCD/Atlantisに `/etc/hosts` なしでアクセスする3つの方法。

### [🛠️ トラブルシューティング](./guides/troubleshooting.md)
よくある問題と解決策。

---

## 🔧 開発者向け

### [CI/CDセットアップ](./development/ci-setup.md)
GitHub ActionsでのCI/CD設定。

### [Moleculeテスト](./development/molecule-testing.md)
Ansibleロールのテスト方法。

---

## 📂 ディレクトリ構成

```
docs/
├── README.md                    # このファイル
├── guides/                      # ユーザーガイド
│   ├── quickstart.md            # クイックスタート
│   ├── ip-management.md         # IP管理ガイド
│   ├── service-access.md        # サービスアクセスガイド
│   └── troubleshooting.md       # トラブルシューティング
├── development/                 # 開発者向けドキュメント
│   ├── ci-setup.md              # CI/CD設定
│   └── molecule-testing.md      # テスト方法
└── archived/                    # 古いドキュメント（参照用）
    ├── IMPLEMENTATION_SUMMARY.md
    ├── FINAL_SUMMARY.md
    ├── DNS_FREE_ACCESS.md
    ├── environment_ip_management.md
    └── ...
```

---

## 🎯 よくある質問

### 初めてクラスタを構築する
→ [クイックスタート](./guides/quickstart.md)を参照

### IPアドレスを変更したい
→ [IP管理ガイド](./guides/ip-management.md#ip設定変更手順)を参照

### ArgoCDにアクセスできない
→ [サービスアクセスガイド](./guides/service-access.md#方法1-kubectl-port-forward最も簡単)を参照

### Podが起動しない
→ [トラブルシューティング](./guides/troubleshooting.md#flannel-cni---pod間通信の問題)を参照

---

## 📖 関連リンク

- [プロジェクトREADME](../README.md) - プロジェクト全体の概要
- [Makefile](../Makefile) - すべてのコマンド定義
- [CLAUDE.md](../CLAUDE.md) - Claude Code向けのガイダンス

---

## 🆘 サポート

問題が解決しない場合：

1. [トラブルシューティング](./guides/troubleshooting.md)を確認
2. `make help` でコマンド一覧を表示
3. `make env-info` で環境設定を確認
4. `make status` でクラスタの状態を確認

---

## 🔄 ドキュメント更新履歴

### 2026-01-18
- ドキュメント構造を全面刷新
- 重複ドキュメントを統合
- guides/ と development/ にディレクトリ分け
- クイックスタートガイドを追加
- IP管理とサービスアクセスガイドを統合・改善
