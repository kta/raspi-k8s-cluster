.PHONY: help
help: ## このヘルプメッセージを表示
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
	./scripts/generate_tfvars.sh $(INVENTORY)

.PHONY: patch-argocd-apps
patch-argocd-apps: ## ArgoCD Application マニフェストを環境に合わせて更新
	@echo "🔄 ArgoCD Applicationを更新中 (環境: $(ENVIRONMENT))..."
	./scripts/patch_argocd_apps.sh $(ENVIRONMENT)

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

.PHONY: port-forward-all
port-forward-all: ## 全サービスにポートフォワード
	./scripts/port_forward_services.sh all

.PHONY: setup-local-dns
setup-local-dns: ## dnsmasq でローカルDNSを設定（要 sudo）
	@echo "🔧 ローカルDNSを設定中 (環境: $(ENVIRONMENT))..."
	./scripts/setup_local_dns.sh $(ENVIRONMENT)

.PHONY: show-ingress-urls
show-ingress-urls: ## nip.io/sslip.io を使ったIngress URLを表示
	./scripts/generate_ingress_urls.sh $(ENVIRONMENT)

# ==========================================
# Phase 1: OS設定 & Kubeadm構築 (Ansible)
# ==========================================

.PHONY: ssh-copy-keys
ssh-copy-keys: ## SSH公開鍵を各Raspberry Piにコピー
	ssh-copy-id -i ~/.ssh/id_ed25519.pub pi@192.168.1.101
	ssh-copy-id -i ~/.ssh/id_ed25519.pub pi@192.168.1.102
	ssh-copy-id -i ~/.ssh/id_ed25519.pub pi@192.168.1.103

.PHONY: ansible-setup
ansible-setup: generate-tfvars patch-argocd-apps ## Ansibleでクラスターをセットアップ
	cd ansible && ansible-playbook -i inventory/inventory.ini site.yml

.PHONY: ansible-setup-vagrant
ansible-setup-vagrant: ## Vagrant環境でクラスターをセットアップ
	$(MAKE) ENV=vagrant generate-tfvars
	$(MAKE) ENV=vagrant patch-argocd-apps
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
ansible-dev-debug: ## クラスター開発用にsetup（Vagrant再構築＋Ansible実行＋検証）
	vagrant destroy -f
	vagrant up
	cd ansible 
	ansible-playbook -i inventory/inventory_vagrant.ini site.yml
	ansible-playbook -i inventory/inventory_vagrant.ini fetch-kubeconfig.yml
	ansible-playbook -i inventory/inventory_vagrant.ini verify.yml


# ==========================================
# Phase 2: インフラBootstrap (Terraform)
# ==========================================

.PHONY: terraform-init
terraform-init: ## Terraformを初期化
	cd terraform/bootstrap && terraform init

.PHONY: terraform-plan
terraform-plan: ## Terraformプランを表示
	@if [ ! -f terraform/bootstrap/terraform.auto.tfvars ]; then \
		echo "⚠️  terraform.auto.tfvars が見つかりません。生成します..."; \
		$(MAKE) generate-tfvars ENV=$(ENVIRONMENT); \
	else \
		./scripts/verify_tfvars_environment.sh $(ENVIRONMENT) || \
		(echo "再生成中..." && $(MAKE) generate-tfvars ENV=$(ENVIRONMENT)); \
	fi
	cd terraform/bootstrap && terraform plan

.PHONY: terraform-apply
terraform-apply: ## Terraformを適用 (ArgoCD等をインストール)
	@if [ ! -f terraform/bootstrap/terraform.auto.tfvars ]; then \
		echo "⚠️  terraform.auto.tfvars が見つかりません。生成します..."; \
		$(MAKE) generate-tfvars ENV=$(ENVIRONMENT); \
	else \
		./scripts/verify_tfvars_environment.sh $(ENVIRONMENT) || \
		(echo "再生成中..." && $(MAKE) generate-tfvars ENV=$(ENVIRONMENT)); \
	fi
	cd terraform/bootstrap && terraform apply

.PHONY: terraform-apply-vagrant
terraform-apply-vagrant: ## Vagrant環境でTerraformを適用
	$(MAKE) terraform-apply ENV=vagrant

.PHONY: terraform-destroy
terraform-destroy: ## Terraformリソースを削除
	cd terraform/bootstrap && terraform destroy

# ==========================================
# Phase 3: GitOps管理 (ArgoCD)
# ==========================================

.PHONY: argocd-bootstrap
argocd-bootstrap: ## ArgoCD Root Appを適用
	kubectl apply -f k8s/bootstrap/root-app.yaml

.PHONY: argocd-sync
argocd-sync: ## すべてのArgoCD Appを同期
	argocd app sync --async --prune --self-heal -l app.kubernetes.io/instance=root

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
setup-all: ## 全フェーズを実行（実機環境）
	@echo "🚀 全フェーズのセットアップを開始 (環境: $(ENVIRONMENT))..."
	$(MAKE) env-info ENV=$(ENVIRONMENT)
	$(MAKE) generate-tfvars ENV=$(ENVIRONMENT)
	$(MAKE) patch-argocd-apps ENV=$(ENVIRONMENT)
	$(MAKE) validate-setup ENV=$(ENVIRONMENT)
	$(MAKE) ssh-copy-keys
	$(MAKE) ansible-setup ENV=$(ENVIRONMENT)
	$(MAKE) fetch-kubeconfig
	$(MAKE) terraform-apply ENV=$(ENVIRONMENT)
	$(MAKE) argocd-bootstrap
	@echo "✅ すべてのセットアップが完了しました！"
	@echo "次のコマンドでクラスターの状態を確認してください: make status"

.PHONY: setup-all-vagrant
setup-all-vagrant: ## 全フェーズを実行（Vagrant環境）
	@echo "🚀 Vagrant環境の全フェーズセットアップを開始..."
	$(MAKE) env-info ENV=vagrant
	$(MAKE) generate-tfvars ENV=vagrant
	$(MAKE) patch-argocd-apps ENV=vagrant
	$(MAKE) validate-setup ENV=vagrant
	$(MAKE) vagrant-up
	$(MAKE) ansible-setup-vagrant
	$(MAKE) fetch-kubeconfig-vagrant
	$(MAKE) terraform-apply ENV=vagrant
	$(MAKE) argocd-bootstrap
	@echo "✅ Vagrant環境のセットアップが完了しました！"
	@echo "次のコマンドでクラスターの状態を確認してください: make status"
