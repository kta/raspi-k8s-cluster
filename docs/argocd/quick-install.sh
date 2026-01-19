#!/bin/bash
# =============================================================================
# ArgoCD クイックインストールスクリプト
# =============================================================================
# 使い方: ./quick-install.sh
#
# このスクリプトは対話形式で各ステップを実行します。
# 各コマンドの実行前に確認を求めます。
# =============================================================================

set -e

# 色の定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ヘルパー関数
print_header() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_step() {
    echo -e "${BLUE}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

confirm() {
    echo ""
    echo -e "${YELLOW}次のコマンドを実行します:${NC}"
    echo -e "${GREEN}  $ $1${NC}"
    echo ""
    read -p "実行しますか? [Y/n]: " response
    case "$response" in
        [nN][oO]|[nN])
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

# バナー表示
clear
cat << 'EOF'

     _                   ____ ____    ___           _        _ _
    / \   _ __ __ _  ___|  _ \  _ \  |_ _|_ __  ___| |_ __ _| | |
   / _ \ | '__/ _` |/ _ \ |_) | | | | | || '_ \/ __| __/ _` | | |
  / ___ \| | | (_| | (_) |  _ <| |_| | | || | | \__ \ || (_| | | |
 /_/   \_\_|  \__, |\___/|_| \_\___/  |___|_| |_|___/\__\__,_|_|_|
              |___/

         Raspberry Pi Kubernetes Cluster Edition
         ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

echo "このスクリプトはArgoCDを対話形式でインストールします。"
echo "各ステップで確認を行いながら進めます。"
echo ""
read -p "続行しますか? [Y/n]: " start_response
if [[ "$start_response" =~ ^[nN] ]]; then
    echo "インストールを中止しました。"
    exit 0
fi

# =============================================================================
# Step 0: 前提条件の確認
# =============================================================================
print_header "Step 0: 前提条件の確認"

print_step "kubectlの確認..."
if command -v kubectl &> /dev/null; then
    print_success "kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client | head -1)"
else
    print_error "kubectlがインストールされていません"
    exit 1
fi

print_step "Helmの確認..."
if command -v helm &> /dev/null; then
    print_success "helm: $(helm version --short)"
else
    print_error "Helmがインストールされていません"
    echo ""
    echo "インストール方法:"
    echo "  macOS: brew install helm"
    echo "  Linux: curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
    exit 1
fi

print_step "Kubernetesクラスタへの接続確認..."
if kubectl cluster-info &> /dev/null; then
    print_success "クラスタに接続済み"
    kubectl get nodes
else
    print_error "Kubernetesクラスタに接続できません"
    echo "kubeconfigを確認してください"
    exit 1
fi

# =============================================================================
# Step 1: Namespaceの作成
# =============================================================================
print_header "Step 1: Namespaceの作成"

if kubectl get namespace argocd &> /dev/null; then
    print_warning "argocd namespace は既に存在します"
else
    if confirm "kubectl create namespace argocd"; then
        kubectl create namespace argocd
        print_success "Namespace 'argocd' を作成しました"
    else
        print_info "スキップしました"
    fi
fi

# =============================================================================
# Step 2: Helmリポジトリの追加
# =============================================================================
print_header "Step 2: Helmリポジトリの追加"

if confirm "helm repo add argo https://argoproj.github.io/argo-helm"; then
    helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
    print_success "Helmリポジトリを追加しました"
else
    print_info "スキップしました"
fi

if confirm "helm repo update"; then
    helm repo update
    print_success "リポジトリを更新しました"
else
    print_info "スキップしました"
fi

# =============================================================================
# Step 3: ArgoCDのインストール
# =============================================================================
print_header "Step 3: ArgoCDのインストール"

print_info "使用するvalues.yaml: ${SCRIPT_DIR}/../../terraform/bootstrap/argocd-values.yaml"
echo ""
echo "主な設定:"
echo "  - サービスタイプ: NodePort (30443)"
echo "  - HTTPS: 無効 (--insecure)"
echo "  - リソース制限: Raspberry Pi向けに最適化"
echo ""

INSTALL_CMD="helm install argocd argo/argo-cd --namespace argocd --values ${SCRIPT_DIR}/../../terraform/bootstrap/argocd-values.yaml --wait"

if confirm "$INSTALL_CMD"; then
    echo ""
    print_info "インストール中... (数分かかる場合があります)"
    echo ""

    if helm install argocd argo/argo-cd \
        --namespace argocd \
        --values "${SCRIPT_DIR}/../../terraform/bootstrap/argocd-values.yaml" \
        --wait \
        --timeout 10m; then
        print_success "ArgoCDをインストールしました"
    else
        print_error "インストールに失敗しました"
        echo ""
        echo "トラブルシューティング:"
        echo "  kubectl get pods -n argocd"
        echo "  kubectl describe pods -n argocd"
        exit 1
    fi
else
    print_info "スキップしました"
    echo "手動でインストールする場合:"
    echo "  $INSTALL_CMD"
fi

# =============================================================================
# Step 4: インストール確認
# =============================================================================
print_header "Step 4: インストール確認"

print_step "Podの状態を確認中..."
kubectl get pods -n argocd

echo ""
print_step "Serviceの状態を確認中..."
kubectl get svc -n argocd

# =============================================================================
# Step 5: 初期パスワードの取得
# =============================================================================
print_header "Step 5: 初期パスワードの取得"

print_step "管理者の初期パスワードを取得中..."
echo ""

ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)

if [ -n "$ADMIN_PASSWORD" ]; then
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│  ArgoCD 管理者ログイン情報                                 │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│                                                             │"
    echo "│  Username: admin                                            │"
    echo "│  Password: ${ADMIN_PASSWORD}                                │"
    echo "│                                                             │"
    echo "└─────────────────────────────────────────────────────────────┘"
else
    print_warning "初期パスワードを取得できませんでした"
    echo "以下のコマンドで取得できます:"
    echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
fi

# =============================================================================
# Step 6: アクセス情報
# =============================================================================
print_header "Step 6: アクセス情報"

# NodeのIPを取得
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)

if [ -z "$NODE_IP" ]; then
    NODE_IP="<NODE_IP>"
fi

echo "┌─────────────────────────────────────────────────────────────┐"
echo "│  ArgoCD Web UI アクセス                                     │"
echo "├─────────────────────────────────────────────────────────────┤"
echo "│                                                             │"
echo "│  URL: https://${NODE_IP}:30443                              │"
echo "│                                                             │"
echo "│  ※ 自己署名証明書のため、ブラウザで警告が表示されます      │"
echo "│  ※ 「詳細設定」から「安全でないページに進む」を選択        │"
echo "│                                                             │"
echo "└─────────────────────────────────────────────────────────────┘"

echo ""
echo "代替アクセス方法 (ポートフォワード):"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  → https://localhost:8080 でアクセス"

# =============================================================================
# 完了
# =============================================================================
print_header "インストール完了"

cat << 'EOF'

  ╔═══════════════════════════════════════════════════════════════╗
  ║                                                               ║
  ║   🎉 ArgoCD のインストールが完了しました！                    ║
  ║                                                               ║
  ║   次のステップ:                                               ║
  ║   1. Web UIにアクセスしてログイン                             ║
  ║   2. 初期パスワードを変更                                     ║
  ║   3. Gitリポジトリを登録してアプリケーションをデプロイ        ║
  ║                                                               ║
  ║   詳細は INSTALL.md を参照してください                        ║
  ║                                                               ║
  ╚═══════════════════════════════════════════════════════════════╝

EOF
