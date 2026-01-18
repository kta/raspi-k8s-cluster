# 開発者向けドキュメント

このディレクトリには、プロジェクトの開発に関するドキュメントが含まれています。

## 📚 コンテンツ

### [CI/CDセットアップ](./ci-setup.md)
GitHub ActionsでのCI/CD設定方法。

### [Moleculeテスト](./molecule-testing.md)
Ansibleロールのテスト方法とMoleculeの使用方法。

## 🔧 開発ワークフロー

### ローカル開発
```bash
# Vagrant環境で開発
make vagrant-up
make ansible-setup-vagrant
make status
```

### 変更のテスト
```bash
# Vagrant環境で完全リビルド
make ansible-dev-debug

# 検証
make ansible-verify
```

### CI/CD
- プッシュ時: リンティング（shellcheck、ansible-lint）
- PR作成時: Vagrant環境でフルテスト
- マージ後: ドキュメント更新

## 📝 コーディング規約

### Ansible
- `ansible-lint` を通過すること
- 複雑なロジックはシェルスクリプトに委譲
- 冪等性を保つ

### シェルスクリプト
- `shellcheck` を通過すること
- エラーハンドリングを適切に実装
- ログ出力を適切に行う

### Terraform
- `terraform fmt` でフォーマット
- 変数は `variables.tf` に定義
- 環境固有の値は `terraform.auto.tfvars` で管理（自動生成）

## 🧪 テスト

### Ansible
```bash
# Molecule テスト（該当ロールがある場合）
cd ansible/roles/example
molecule test
```

### シェルスクリプト
```bash
# shellcheck
shellcheck ansible/scripts/*.sh
shellcheck scripts/*.sh
```

### Terraform
```bash
# プラン確認
cd terraform/bootstrap
terraform plan
```

## 📖 関連リンク

- [プロジェクトREADME](../../README.md)
- [ドキュメントトップ](../README.md)
- [クイックスタート](../guides/quickstart.md)
