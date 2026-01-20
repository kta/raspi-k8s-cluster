#!/usr/bin/env bash
# =============================================================================
# Setup Local DNS for environment-specific domains
# =============================================================================
# This script configures dnsmasq to resolve domains to the Ingress LoadBalancer IP.
#
# Production: *.raspi.local → Production Ingress IP
# Vagrant:    *.vagrant.local → Vagrant Ingress IP
#
# Usage:
#   ./setup_local_dns.sh [environment]
#
# Examples:
#   ./setup_local_dns.sh production
#   ./setup_local_dns.sh vagrant
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENVIRONMENT="${1:-production}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Validate environment
if [[ "$ENVIRONMENT" != "production" && "$ENVIRONMENT" != "vagrant" ]]; then
log_error "Environment must be 'production' or 'vagrant'"
exit 1
fi

# Determine inventory file and domain
if [[ "$ENVIRONMENT" == "production" ]]; then
INVENTORY_FILE="$PROJECT_ROOT/ansible/inventory/inventory.ini"
DOMAIN="raspi.local"
else
INVENTORY_FILE="$PROJECT_ROOT/ansible/inventory/inventory_vagrant.ini"
DOMAIN="vagrant.local"
fi

if [[ ! -f "$INVENTORY_FILE" ]]; then
log_error "Inventory file not found: $INVENTORY_FILE"
exit 1
fi

# Extract ingress_ip
INGRESS_IP=$(grep "^ingress_ip=" "$INVENTORY_FILE" | head -1 | cut -d'=' -f2 | tr -d ' ')

if [[ -z "$INGRESS_IP" ]]; then
log_error "ingress_ip not found in inventory file"
exit 1
fi

log_info "Environment: $ENVIRONMENT"
log_info "Domain: *.$DOMAIN"
log_info "Ingress IP: $INGRESS_IP"
echo ""

# Detect OS
OS="$(uname -s)"

case "$OS" in
Darwin)
log_info "Detected macOS"
echo ""

# Check if dnsmasq is installed
if ! command -v dnsmasq &>/dev/null; then
log_error "dnsmasq is not installed"
echo ""
echo "Install with:"
echo "  brew install dnsmasq"
exit 1
fi

# dnsmasq configuration directory
DNSMASQ_DIR="/opt/homebrew/etc/dnsmasq.d"
if [[ ! -d "$DNSMASQ_DIR" ]]; then
DNSMASQ_DIR="/usr/local/etc/dnsmasq.d"
fi

mkdir -p "$DNSMASQ_DIR" 2>/dev/null || true

# Create configuration file
CONFIG_FILE="$DNSMASQ_DIR/raspi-k8s-${ENVIRONMENT}.conf"

log_info "Creating dnsmasq config: $CONFIG_FILE"
sudo tee "$CONFIG_FILE" >/dev/null <<EOF
# Raspberry Pi Kubernetes Cluster DNS Configuration
# Environment: $ENVIRONMENT
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

# Resolve *.$DOMAIN to Ingress LoadBalancer IP
address=/$DOMAIN/$INGRESS_IP
address=/.$DOMAIN/$INGRESS_IP
EOF

log_info "✅ Configuration file created"
echo ""

# Restart dnsmasq
log_info "Restarting dnsmasq..."
sudo brew services restart dnsmasq || sudo brew services start dnsmasq

log_info "✅ dnsmasq restarted"
echo ""

# macOS DNS resolver configuration
RESOLVER_DIR="/etc/resolver"
sudo mkdir -p "$RESOLVER_DIR"

log_info "Creating macOS resolver config..."
sudo tee "$RESOLVER_DIR/$DOMAIN" >/dev/null <<EOF
nameserver 127.0.0.1
EOF

log_info "✅ macOS resolver configured"
echo ""

# Clear DNS cache
log_info "Clearing DNS cache..."
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder

log_info "✅ DNS cache cleared"
;;

Linux)
log_info "Detected Linux"
echo ""

# Check if dnsmasq is installed
if ! command -v dnsmasq &>/dev/null; then
log_error "dnsmasq is not installed"
echo ""
echo "Install with:"
echo "  sudo apt-get install dnsmasq     # Debian/Ubuntu"
echo "  sudo yum install dnsmasq         # CentOS/RHEL"
exit 1
fi

# Create configuration file
CONFIG_FILE="/etc/dnsmasq.d/raspi-k8s-${ENVIRONMENT}.conf"

log_info "Creating dnsmasq config: $CONFIG_FILE"
sudo tee "$CONFIG_FILE" >/dev/null <<EOF
# Raspberry Pi Kubernetes Cluster DNS Configuration
# Environment: $ENVIRONMENT
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

# Resolve *.$DOMAIN to Ingress LoadBalancer IP
address=/$DOMAIN/$INGRESS_IP
address=/.$DOMAIN/$INGRESS_IP
EOF

log_info "✅ Configuration file created"
echo ""

# Restart dnsmasq
log_info "Restarting dnsmasq..."
sudo systemctl restart dnsmasq

log_info "✅ dnsmasq restarted"
;;

*)
log_error "Unsupported OS: $OS"
exit 1
;;
esac

echo ""
echo "=========================================="
echo -e "${GREEN}✅ Local DNS setup completed!${NC}"
echo ""
echo "The following domains are now accessible:"
if [[ "$ENVIRONMENT" == "production" ]]; then
echo "  🔹 https://argocd.raspi.local"
echo "  🔹 https://atlantis.raspi.local"
echo "  🔹 https://traefik.raspi.local"
else
echo "  🔹 https://argocd.vagrant.local"
echo "  🔹 https://atlantis.vagrant.local"
echo "  🔹 https://traefik.vagrant.local"
fi
echo ""
echo "Verification:"
if [[ "$ENVIRONMENT" == "production" ]]; then
echo "  nslookup argocd.raspi.local"
echo "  ping -c 1 argocd.raspi.local"
else
echo "  nslookup argocd.vagrant.local"
echo "  ping -c 1 argocd.vagrant.local"
fi
echo ""
echo -e "${YELLOW}⚠️  HTTPS Warning:${NC}"
echo "  Browser will show certificate warnings until you:"
echo "  1. Generate CA certificate: make generate-ca ENV=$ENVIRONMENT"
echo "  2. Install CA on cluster: make install-ca ENV=$ENVIRONMENT"
echo "  3. Trust CA in browser: make trust-ca ENV=$ENVIRONMENT"
echo ""
echo "Removal:"
if [[ "$OS" == "Darwin" ]]; then
echo "  sudo rm $CONFIG_FILE"
echo "  sudo rm /etc/resolver/$DOMAIN"
echo "  sudo brew services restart dnsmasq"
else
echo "  sudo rm $CONFIG_FILE"
echo "  sudo systemctl restart dnsmasq"
fi
echo "=========================================="
