# ==========================================
# ヘルプとデフォルト設定
# ==========================================

.PHONY: help
help: ## 利用可能なコマンド一覧を表示
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help

# ==========================================
# 環境検出とセットアップ
# ==========================================

# 環境変数 ENV で環境を指定可能 (production または vagrant)
# 指定がない場合は inventory.ini から自動検出
ENV ?= auto

# インベントリファイルの決定
ifeq ($(ENV),vagrant)
	INVENTORY := ansible/inventory/inventory_vagrant.ini
	ENVIRONMENT := vagrant
else ifeq ($(ENV),production)
	INVENTORY := ansible/inventory/inventory.ini
	ENVIRONMENT := production
else
	# 自動検出: デフォルトは production
	INVENTORY := ansible/inventory/inventory.ini
	ENVIRONMENT := production
endif

.PHONY: env-info
env-info: ## 現在の環境設定を表示
	@echo "📋 環境設定:"
	@echo "  ENV: $(ENV)"
	@echo "  ENVIRONMENT: $(ENVIRONMENT)"
	@echo "  INVENTORY: $(INVENTORY)"

.PHONY: generate-tfvars
generate-tfvars: ## Ansible インベントリから terraform.auto.tfvars を生成
	@echo "🔄 Terraform変数を生成中 (環境: $(ENVIRONMENT))..."
	./scripts/generate_tfvars.sh $(ENVIRONMENT)


.PHONY: validate-setup
validate-setup: ## 環境設定を検証
	@echo "🔍 環境設定を検証中 (環境: $(ENVIRONMENT))..."
	./scripts/validate_setup.sh $(ENVIRONMENT)

# ==========================================
# サービスアクセス（/etc/hosts 不要）
# ==========================================

.PHONY: port-forward-argocd
port-forward-argocd: ## ArgoCD にポートフォワード (http://localhost:8080)
	./scripts/port_forward_services.sh argocd

.PHONY: port-forward-atlantis
port-forward-atlantis: ## Atlantis にポートフォワード (http://localhost:4141)
	./scripts/port_forward_services.sh atlantis

.PHONY: port-forward-traefik
port-forward-traefik: ## Traefik にポートフォワード (http://localhost:9000)
	./scripts/port_forward_services.sh traefik

.PHONY: port-forward-grafana
port-forward-grafana: ## Grafana にポートフォワード (http://localhost:3000)
	./scripts/port_forward_services.sh grafana

.PHONY: port-forward-prometheus
port-forward-prometheus: ## Prometheus にポートフォワード (http://localhost:9090)
	./scripts/port_forward_services.sh prometheus

.PHONY: port-forward-all
port-forward-all: ## 全サービスにポートフォワード
	./scripts/port_forward_services.sh all

.PHONY: setup-local-dns
setup-local-dns: ## dnsmasq でローカルDNSを設定（要 sudo）
	@echo "🔧 ローカルDNSを設定中 (環境: $(ENVIRONMENT))..."
	./scripts/setup_local_dns.sh $(ENVIRONMENT)

.PHONY: generate-ca
generate-ca: ## 自己署名CA証明書を生成（ローカル開発用）
	@echo "🔐 CA証明書を生成中 (環境: $(ENVIRONMENT))..."
	./scripts/generate_ca_cert.sh certs $(ENVIRONMENT)

.PHONY: install-ca
install-ca: ## CA証明書をKubernetesクラスターにインストール
	@echo "📦 CA証明書をKubernetesにインストール中..."
	@if [ ! -f certs/ca-secret.yaml ]; then \
		echo "❌ CA証明書が見つかりません。まず 'make generate-ca ENV=$(ENVIRONMENT)' を実行してください"; \
		exit 1; \
	fi
	kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f certs/ca-secret.yaml
	@echo "✅ CA証明書がインストールされました"

.PHONY: trust-ca
trust-ca: ## CA証明書をブラウザ/システムで信頼（要 sudo）
	@echo "🔒 CA証明書を信頼設定中 (環境: $(ENVIRONMENT))..."
	./scripts/trust_ca_cert.sh certs/ca.crt $(ENVIRONMENT)

.PHONY: setup-https
setup-https: generate-ca install-ca trust-ca ## HTTPSセットアップ完全自動化（CA生成→インストール→信頼）
	@echo "✅ HTTPSセットアップが完了しました！"
	@echo ""
	@echo "🌐 以下のURLにHTTPSでアクセス可能です:"
	@if [ "$(ENVIRONMENT)" = "vagrant" ]; then \
		echo "  https://argocd.vagrant.local"; \
		echo "  https://atlantis.vagrant.local"; \
	else \
		echo "  https://argocd.raspi.local"; \
		echo "  https://atlantis.raspi.local"; \
	fi
	@echo ""
	@echo "⚠️  まだDNSを設定していない場合は 'make setup-local-dns ENV=$(ENVIRONMENT)' を実行してください"

.PHONY: show-ingress-urls
show-ingress-urls: ## nip.io/sslip.io を使ったIngress URLを表示
	./scripts/generate_ingress_urls.sh $(ENVIRONMENT)

# ==========================================
# Phase 1: OS設定 & Kubeadm構築 (Ansible)
# ==========================================

.PHONY: ssh-copy-keys
ssh-copy-keys: ## SSH公開鍵を各ノードにコピー（初回のみ）
	@echo "🔑 SSH公開鍵をコピー中..."
	ssh-copy-id -i ~/.ssh/id_ed25519.pub pi@192.168.1.101 || true
	ssh-copy-id -i ~/.ssh/id_ed25519.pub pi@192.168.1.102 || true
	ssh-copy-id -i ~/.ssh/id_ed25519.pub pi@192.168.1.103 || true
	@echo "✅ SSH鍵のコピーが完了しました"

.PHONY: ansible-setup
ansible-setup: generate-tfvars ## 【Phase 1】Ansibleでクラスタをセットアップ（本番環境）
	@echo "🔧 クラスタをセットアップ中 (環境: $(ENVIRONMENT))..."
	cd ansible && ansible-playbook -i inventory/inventory.ini site.yml

.PHONY: ansible-setup-vagrant
ansible-setup-vagrant: ## 【Phase 1】Ansibleでクラスタをセットアップ（Vagrant環境）
	@echo "🔧 Vagrant環境のクラスタをセットアップ中..."
	$(MAKE) ENV=vagrant generate-tfvars
	vagrant up
	cd ansible && ansible-playbook -i inventory/inventory_vagrant.ini site.yml

.PHONY: fetch-kubeconfig
fetch-kubeconfig: ## kubeconfigを取得
	cd ansible && ansible-playbook -i inventory/inventory.ini fetch-kubeconfig.yml

.PHONY: fetch-kubeconfig-vagrant
fetch-kubeconfig-vagrant: ## Vagrant環境でkubeconfigを取得
	cd ansible && ansible-playbook -i inventory/inventory_vagrant.ini fetch-kubeconfig.yml

.PHONY: ansible-verify
ansible-verify: ## クラスターを検証
	cd ansible && ansible-playbook -i inventory/inventory.ini verify.yml

.PHONY: ansible-reset
ansible-reset: ## クラスターをリセット
	cd ansible && ansible-playbook -i inventory/inventory.ini reset.yml

.PHONY: ansible-upgrade
ansible-upgrade: ## クラスターをアップグレード
	cd ansible && ansible-playbook -i inventory/inventory.ini upgrade.yml

.PHONY: ansible-dev-debug
ansible-dev-debug: ## Vagrant環境の完全リビルド（開発用）
	vagrant destroy -f
	vagrant up
	cd ansible && \
		ansible-playbook -i inventory/inventory_vagrant.ini site.yml && \
		ansible-playbook -i inventory/inventory_vagrant.ini fetch-kubeconfig.yml && \
		ansible-playbook -i inventory/inventory_vagrant.ini verify.yml


# ==========================================
# Phase 2: インフラBootstrap (Terraform)
# ==========================================

.PHONY: terraform-init
terraform-init: ## Terraformを初期化
	@echo "🔧 Terraform初期化中 (環境: $(ENVIRONMENT))..."
	cd terraform/environments/$(ENVIRONMENT) && terraform init

.PHONY: terraform-plan
terraform-plan: ## Terraformプランを表示
	@if [ ! -f terraform/environments/$(ENVIRONMENT)/terraform.auto.tfvars ]; then \
		echo "⚠️  terraform.auto.tfvars が見つかりません。生成します..."; \
		$(MAKE) generate-tfvars ENV=$(ENVIRONMENT); \
	fi
	@echo "📋 Terraformプランを実行中 (環境: $(ENVIRONMENT))..."
	cd terraform/environments/$(ENVIRONMENT) && terraform plan

.PHONY: terraform-apply
terraform-apply: ## 【Phase 2】Terraform適用（ArgoCDインストール）
	@if [ ! -f terraform/environments/$(ENVIRONMENT)/terraform.auto.tfvars ]; then \
		echo "⚠️  terraform.auto.tfvars が見つかりません。生成します..."; \
		$(MAKE) generate-tfvars ENV=$(ENVIRONMENT); \
	fi
	@echo "🚀 Terraformを適用中 (環境: $(ENVIRONMENT))..."
	@echo "📦 ステージ1: ArgoCDインストール（CRDセットアップ）"
	cd terraform/environments/$(ENVIRONMENT) && \
		terraform apply -target=module.argocd.kubernetes_namespace_v1.this \
		                -target=module.argocd.helm_release.this \
		                -target=module.argocd.null_resource.wait_for_argocd_crds \
		                -target=module.argocd.kubernetes_config_map_v1.environment_config \
		                -target=module.sealed_secrets \
		                -target=module.atlantis_secrets
	@echo "✅ ステージ1完了。ArgoCD CRDが利用可能になりました"
	@echo "📦 ステージ2: ApplicationSetデプロイ"
	cd terraform/environments/$(ENVIRONMENT) && terraform apply

.PHONY: terraform-apply-auto-approve
terraform-apply-auto-approve: ## Terraform適用（自動承認）
	@if [ ! -f terraform/environments/$(ENVIRONMENT)/terraform.auto.tfvars ]; then \
		echo "⚠️  terraform.auto.tfvars が見つかりません。生成します..."; \
		$(MAKE) generate-tfvars ENV=$(ENVIRONMENT); \
	fi
	@echo "🚀 Terraformを適用中 (環境: $(ENVIRONMENT)) [自動承認]..."
	@echo "📦 ステージ1: ArgoCDインストール（CRDセットアップ）"
	cd terraform/environments/$(ENVIRONMENT) && \
		terraform apply -auto-approve \
		                -target=module.argocd.kubernetes_namespace_v1.this \
		                -target=module.argocd.helm_release.this \
		                -target=module.argocd.null_resource.wait_for_argocd_crds \
		                -target=module.argocd.kubernetes_config_map_v1.environment_config \
		                -target=module.sealed_secrets \
		                -target=module.atlantis_secrets
	@echo "✅ ステージ1完了。ArgoCD CRDが利用可能になりました"
	@echo "📦 ステージ2: ApplicationSetデプロイ"
	cd terraform/environments/$(ENVIRONMENT) && terraform apply -auto-approve

.PHONY: terraform-destroy
terraform-destroy: ## Terraformで作成したリソースを削除
	@echo "🗑️  Terraformリソースを削除中 (環境: $(ENVIRONMENT))..."
	cd terraform/environments/$(ENVIRONMENT) && terraform destroy

.PHONY: terraform-output
terraform-output: ## Terraform outputを表示
	cd terraform/environments/$(ENVIRONMENT) && terraform output

.PHONY: terraform-fmt
terraform-fmt: ## Terraformコードをフォーマット
	cd terraform && terraform fmt -recursive

.PHONY: terraform-validate
terraform-validate: ## Terraformコードを検証
	@echo "🔍 Terraform検証中 (環境: $(ENVIRONMENT))..."
	cd terraform/environments/$(ENVIRONMENT) && terraform validate

.PHONY: terraform-apply-vagrant
terraform-apply-vagrant: ## Vagrant環境でTerraformを適用
	$(MAKE) terraform-apply ENV=vagrant

# ==========================================
# Phase 3: GitOps管理 (ArgoCD)
# ==========================================

.PHONY: argocd-bootstrap
argocd-bootstrap: ## 【Phase 3】ArgoCD ApplicationSet適用（GitOps開始）
	@echo "🎯 ArgoCD ApplicationSetを適用中..."
	@echo "  ⚠️  ApplicationSetはTerraformで管理されています"
	@echo "  📦 terraform apply実行時に自動的に作成されます"
	@echo ""
	@echo "💡 手動で再適用する場合:"
	@echo "  make terraform-apply ENV=$(ENVIRONMENT)"
	@echo ""
	@echo "🔍 確認コマンド:"
	@echo "  kubectl get appset -n argocd"
	@echo "  kubectl get app -n argocd | grep infra-"

.PHONY: argocd-sync
argocd-sync: ## すべてのArgoCD Appを同期
	@echo "🔄 ArgoCD Applicationsを同期中 (環境: $(ENVIRONMENT))..."
	argocd app sync --async --prune infra-$(ENVIRONMENT)

.PHONY: argocd-sync-all
argocd-sync-all: ## すべての環境のArgoCD Appを同期
	@echo "🔄 すべてのArgoCD Applicationsを同期中..."
	argocd app sync --async --prune -l app.kubernetes.io/instance=root

.PHONY: argocd-status
argocd-status: ## ArgoCD Appのステータスを表示
	argocd app list

# ==========================================
# Vagrant操作
# ==========================================

.PHONY: vagrant-up
vagrant-up: ## Vagrant VMを起動
	vagrant up

.PHONY: vagrant-halt
vagrant-halt: ## Vagrant VMを停止
	vagrant halt

.PHONY: vagrant-destroy
vagrant-destroy: ## Vagrant VMを削除
	vagrant destroy -f

.PHONY: vagrant-ssh-primary
vagrant-ssh-primary: ## Primary nodeにSSH接続
	vagrant ssh primary

# ==========================================
# 開発・デバッグ
# ==========================================

.PHONY: k9s
k9s: ## k9sでクラスターを管理
	k9s

.PHONY: status
status: ## クラスターの状態を確認
	@echo "=== Nodes ==="
	@kubectl get nodes
	@echo "\n=== Pods ==="
	@kubectl get pods -A
	@echo "\n=== Services ==="
	@kubectl get svc -A

.PHONY: logs-primary
logs-primary: ## Primary nodeのログを確認
	vagrant ssh primary -c "sudo journalctl -u kubelet -n 100"

# ==========================================
# 完全セットアップ (全フェーズ)
# ==========================================

.PHONY: setup-all
setup-all: ## 【本番環境】全フェーズを一括実行（Phase 1-3）
	@echo "🚀 全フェーズのセットアップを開始 (環境: $(ENVIRONMENT))..."
	$(MAKE) env-info ENV=$(ENVIRONMENT)
	$(MAKE) generate-tfvars ENV=$(ENVIRONMENT)
	$(MAKE) validate-setup ENV=$(ENVIRONMENT)
	$(MAKE) ssh-copy-keys
	$(MAKE) ansible-setup ENV=$(ENVIRONMENT)
	$(MAKE) fetch-kubeconfig
	$(MAKE) terraform-apply ENV=$(ENVIRONMENT)
	$(MAKE) argocd-bootstrap
	@echo "✅ すべてのセットアップが完了しました！"
	@echo ""
	@echo "📊 次のステップ:"
	@echo "  make status              # クラスタ状態確認"
	@echo "  make argocd-status       # ArgoCD App確認"
	@echo "  make port-forward-argocd # ArgoCD UIアクセス"

.PHONY: setup-all-vagrant
setup-all-vagrant: ## 【Vagrant環境】全フェーズを一括実行（Phase 1-3）
	@echo "🚀 Vagrant環境の全フェーズセットアップを開始..."
	$(MAKE) env-info ENV=vagrant
	$(MAKE) generate-tfvars ENV=vagrant
	$(MAKE) validate-setup ENV=vagrant
	vagrant destroy -f
	$(MAKE) vagrant-up
	$(MAKE) ansible-setup-vagrant
	$(MAKE) fetch-kubeconfig-vagrant
	$(MAKE) terraform-apply-auto-approve ENV=vagrant
	$(MAKE) argocd-bootstrap
	@echo "✅ Vagrant環境のセットアップが完了しました！"
	@echo ""
	@echo "📊 次のステップ:"
	@echo "  make status              # クラスタ状態確認"
	@echo "  make argocd-status       # ArgoCD App確認"
	@echo "  make port-forward-argocd # ArgoCD UIアクセス"
