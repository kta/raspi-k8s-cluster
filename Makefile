.PHONY: help
help: ## このヘルプメッセージを表示
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help

# ==========================================
# Phase 1: OS設定 & Kubeadm構築 (Ansible)
# ==========================================

.PHONY: ssh-copy-keys
ssh-copy-keys: ## SSH公開鍵を各Raspberry Piにコピー
	ssh-copy-id -i ~/.ssh/id_ed25519.pub pi@192.168.1.101
	ssh-copy-id -i ~/.ssh/id_ed25519.pub pi@192.168.1.102
	ssh-copy-id -i ~/.ssh/id_ed25519.pub pi@192.168.1.103

.PHONY: ansible-setup
ansible-setup: ## Ansibleでクラスターをセットアップ
	cd ansible && ansible-playbook -i inventory/inventory.ini site.yml

.PHONY: ansible-setup-vagrant
ansible-setup-vagrant: ## Vagrant環境でクラスターをセットアップ
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
	cd ansible && ansible-playbook -i inventory/inventory_vagrant.ini site.yml
	cd ansible-playbook -i inventory/inventory_vagrant.ini fetch-kubeconfig.yml
	cd ansible-playbook -i inventory/inventory_vagrant.ini verify.yml


# ==========================================
# Phase 2: インフラBootstrap (Terraform)
# ==========================================

.PHONY: terraform-init
terraform-init: ## Terraformを初期化
	cd terraform/bootstrap && terraform init

.PHONY: terraform-plan
terraform-plan: ## Terraformプランを表示
	cd terraform/bootstrap && terraform plan

.PHONY: terraform-apply
terraform-apply: ## Terraformを適用 (ArgoCD等をインストール)
	cd terraform/bootstrap && terraform apply

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
setup-all: ansible-setup fetch-kubeconfig terraform-apply argocd-bootstrap ## 全フェーズを実行
	@echo "✅ すべてのセットアップが完了しました！"
	@echo "次のコマンドでクラスターの状態を確認してください: make status"
