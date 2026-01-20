#!/usr/bin/env bash
# =============================================================================
# Trust CA Certificate on Client System
# =============================================================================
# This script installs the self-signed CA certificate to the system/browser
# trust store so that browsers accept certificates issued by the local CA.
#
# Prerequisites:
#   1. CA certificate must exist: certs/ca.crt
#   2. Run generate_ca_cert.sh first if not exists
#
# Usage:
#   ./trust_ca_cert.sh [ca_cert_path] [environment]
#
# Examples:
#   ./trust_ca_cert.sh
#   ./trust_ca_cert.sh certs/ca.crt vagrant
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default CA certificate path
DEFAULT_CA_CERT="$PROJECT_ROOT/certs/ca.crt"
CA_CERT="${1:-$DEFAULT_CA_CERT}"
ENVIRONMENT="${2:-production}"

# Determine domain based on environment
if [[ "$ENVIRONMENT" == "vagrant" ]]; then
DOMAIN="vagrant.local"
CN_NAME="vagrant.local Root CA"
else
DOMAIN="raspi.local"
CN_NAME="raspi.local Root CA"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Check if CA certificate exists
if [[ ! -f "$CA_CERT" ]]; then
log_error "CA certificate not found: $CA_CERT"
echo ""
echo "Generate CA certificate first:"
echo "  make generate-ca ENV=$ENVIRONMENT"
echo "  # or"
echo "  ./scripts/generate_ca_cert.sh certs $ENVIRONMENT"
exit 1
fi

log_info "CA Certificate: $CA_CERT"
log_info "Environment: $ENVIRONMENT"
log_info "Domain: *.$DOMAIN"
echo ""

# Display certificate info
log_info "Certificate details:"
openssl x509 -in "$CA_CERT" -noout -subject -issuer -dates
echo ""

# Detect OS
OS="$(uname -s)"

case "$OS" in
Darwin)
log_info "Detected macOS"
echo ""

log_warn "This will install the CA certificate to the system keychain"
log_warn "You may be prompted for your password"
echo ""
read -p "Continue? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
log_info "Aborted"
exit 0
fi

log_info "Installing CA certificate to system keychain..."
sudo security add-trusted-cert \
-d -r trustRoot \
-k /Library/Keychains/System.keychain \
"$CA_CERT"

log_info "✅ CA certificate installed"
echo ""
log_info "Verifying installation..."
security find-certificate -c "$CN_NAME" /Library/Keychains/System.keychain

echo ""
log_info "✅ Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Restart your browser"
if [[ "$ENVIRONMENT" == "vagrant" ]]; then
echo "  2. Visit https://argocd.vagrant.local"
else
echo "  2. Visit https://argocd.raspi.local"
fi
echo "  3. No certificate warning should appear"
;;

Linux)
log_info "Detected Linux"
echo ""

log_warn "This will install the CA certificate to the system trust store"
echo ""
read -p "Continue? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
log_info "Aborted"
exit 0
fi

# Detect Linux distribution
if [[ -f /etc/debian_version ]]; then
# Debian/Ubuntu
log_info "Detected Debian/Ubuntu"
CA_DIR="/usr/local/share/ca-certificates"
sudo mkdir -p "$CA_DIR"
sudo cp "$CA_CERT" "$CA_DIR/raspi-k8s-${ENVIRONMENT}-ca.crt"
sudo update-ca-certificates

elif [[ -f /etc/redhat-release ]]; then
# CentOS/RHEL/Fedora
log_info "Detected CentOS/RHEL/Fedora"
CA_DIR="/etc/pki/ca-trust/source/anchors"
sudo mkdir -p "$CA_DIR"
sudo cp "$CA_CERT" "$CA_DIR/raspi-k8s-${ENVIRONMENT}-ca.crt"
sudo update-ca-trust

else
log_error "Unsupported Linux distribution"
echo ""
echo "Manual installation:"
echo "  1. Copy $CA_CERT to your system's CA trust directory"
echo "  2. Run your system's CA update command"
exit 1
fi

log_info "✅ CA certificate installed"
echo ""
log_info "✅ Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Restart your browser"
if [[ "$ENVIRONMENT" == "vagrant" ]]; then
echo "  2. Visit https://argocd.vagrant.local"
else
echo "  2. Visit https://argocd.raspi.local"
fi
echo "  3. No certificate warning should appear"
;;

*)
log_error "Unsupported OS: $OS"
echo ""
echo "Manual installation instructions:"
echo ""
echo "📋 macOS:"
echo "  sudo security add-trusted-cert -d -r trustRoot \\"
echo "    -k /Library/Keychains/System.keychain \\"
echo "    $CA_CERT"
echo ""
echo "📋 Windows:"
echo "  1. Double-click $CA_CERT"
echo "  2. Click 'Install Certificate'"
echo "  3. Select 'Local Machine'"
echo "  4. Place in 'Trusted Root Certification Authorities'"
echo ""
echo "📋 Chrome/Chromium (Linux):"
echo "  1. Settings > Privacy and security > Security"
echo "  2. Manage certificates > Authorities"
echo "  3. Import $CA_CERT"
echo ""
echo "📋 Firefox:"
echo "  1. Settings > Privacy & Security"
echo "  2. View Certificates > Authorities"
echo "  3. Import $CA_CERT"
echo "  4. Trust for identifying websites"
exit 1
;;
esac

echo ""
echo "=========================================="
echo -e "${GREEN}✅ Browser Trust Setup Complete${NC}"
echo ""
echo "🔒 Your browser will now trust certificates issued by:"
echo "   $CN_NAME"
echo ""
echo "🌐 Test by visiting:"
if [[ "$ENVIRONMENT" == "vagrant" ]]; then
echo "   https://argocd.vagrant.local"
echo "   https://atlantis.vagrant.local"
else
echo "   https://argocd.raspi.local"
echo "   https://atlantis.raspi.local"
fi
echo ""
echo "🔧 Removal (if needed):"
if [[ "$OS" == "Darwin" ]]; then
echo "   sudo security delete-certificate -c '$CN_NAME' \\"
echo "     /Library/Keychains/System.keychain"
elif [[ "$OS" == "Linux" ]]; then
if [[ -f /etc/debian_version ]]; then
echo "   sudo rm /usr/local/share/ca-certificates/raspi-k8s-${ENVIRONMENT}-ca.crt"
echo "   sudo update-ca-certificates --fresh"
elif [[ -f /etc/redhat-release ]]; then
echo "   sudo rm /etc/pki/ca-trust/source/anchors/raspi-k8s-${ENVIRONMENT}-ca.crt"
echo "   sudo update-ca-trust"
fi
fi
echo "=========================================="
