#!/usr/bin/env bash
# =============================================================================
# Generate Self-Signed CA Certificate for Local Development
# =============================================================================
# This script creates a Certificate Authority (CA) for local development.
# The CA is used by cert-manager to issue certificates for local domains.
# 
# Production: *.raspi.local
# Vagrant:    *.vagrant.local
#
# Usage:
#   ./generate_ca_cert.sh [output_dir] [environment]
#
# Examples:
#   ./generate_ca_cert.sh                    # Default: certs/ production
#   ./generate_ca_cert.sh certs/ vagrant     # Vagrant environment
#
# Output:
#   - ca.key: CA private key
#   - ca.crt: CA certificate (install this in your browser)
#   - ca-secret.yaml: Kubernetes Secret for cert-manager
# =============================================================================

set -euo pipefail

# Configuration
OUTPUT_DIR="${1:-$(pwd)/certs}"
ENVIRONMENT="${2:-production}"
CA_DAYS=3650  # 10 years
COUNTRY="JP"
ORG="Raspi K8s Cluster"

# Determine domain based on environment
if [[ "$ENVIRONMENT" == "vagrant" ]]; then
DOMAIN="vagrant.local"
else
DOMAIN="raspi.local"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Create output directory
mkdir -p "${OUTPUT_DIR}"
cd "${OUTPUT_DIR}"

log_info "Generating CA certificate for *.${DOMAIN}..."
log_info "Environment: $ENVIRONMENT"

# Generate CA private key
if [[ ! -f ca.key ]]; then
    log_info "Creating CA private key..."
    openssl genrsa -out ca.key 4096
else
    log_warn "CA private key already exists, skipping..."
fi

# Generate CA certificate
if [[ ! -f ca.crt ]]; then
    log_info "Creating CA certificate..."
    openssl req -x509 -new -nodes \
        -key ca.key \
        -sha256 \
        -days "${CA_DAYS}" \
        -out ca.crt \
        -subj "/C=${COUNTRY}/O=${ORG}/CN=${DOMAIN} Root CA"
else
    log_warn "CA certificate already exists, skipping..."
fi

# Generate Kubernetes Secret manifest
log_info "Creating Kubernetes Secret manifest..."
cat > ca-secret.yaml <<EOF
# =============================================================================
# Self-Signed CA Secret for cert-manager
# =============================================================================
# This Secret contains the CA certificate and key used by cert-manager
# to issue certificates for local development.
#
# Environment: $ENVIRONMENT
# Domain: *.$DOMAIN
#
# Apply this before deploying cert-manager CA Issuer:
#   kubectl create namespace cert-manager || true
#   kubectl apply -f ca-secret.yaml
# =============================================================================
apiVersion: v1
kind: Secret
metadata:
  name: ca-key-pair
  namespace: cert-manager
type: kubernetes.io/tls
data:
  tls.crt: $(base64 < ca.crt | tr -d '\n')
  tls.key: $(base64 < ca.key | tr -d '\n')
EOF

# Display certificate info
log_info "CA certificate details:"
openssl x509 -in ca.crt -noout -text | grep -E "(Subject:|Not Before|Not After|Public-Key)"

# Success message
echo ""
log_info "✅ CA certificate generated successfully!"
echo ""
echo "📁 Output directory: ${OUTPUT_DIR}"
echo "   - ca.key: CA private key (keep this secret!)"
echo "   - ca.crt: CA certificate (install in your browser)"
echo "   - ca-secret.yaml: Kubernetes Secret manifest"
echo ""
echo "📋 Next steps:"
echo "   1. Apply the Secret to Kubernetes:"
echo "      kubectl create namespace cert-manager || true"
echo "      kubectl apply -f ${OUTPUT_DIR}/ca-secret.yaml"
echo ""
echo "   2. Install ca.crt in your browser/system:"
echo "      - macOS: sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ${OUTPUT_DIR}/ca.crt"
echo "      - Linux: sudo cp ${OUTPUT_DIR}/ca.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates"
echo "      - Windows: Import ca.crt to 'Trusted Root Certification Authorities'"
echo "      - Chrome: Settings > Privacy and security > Security > Manage certificates"
echo ""
echo "   3. Deploy cert-manager CA Issuer:"
echo "      kubectl apply -f k8s/infrastructure/cert-manager-resources/base/ca-issuer.yaml"
echo ""
echo "   4. Verify domains:"
if [[ "$ENVIRONMENT" == "vagrant" ]]; then
echo "      https://argocd.vagrant.local"
echo "      https://atlantis.vagrant.local"
else
echo "      https://argocd.raspi.local"
echo "      https://atlantis.raspi.local"
fi
echo ""
