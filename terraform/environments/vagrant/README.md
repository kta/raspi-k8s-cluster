# Vagrant Environment

Development Kubernetes cluster infrastructure for local testing.

## Network Configuration

- **Environment**: `vagrant`
- **VIP**: `192.168.56.100`
- **MetalLB Range**: `192.168.56.200-192.168.56.220`
- **Ingress IP**: `192.168.56.200`

## Deployed Components

1. **ArgoCD** - GitOps continuous delivery
2. **Sealed Secrets** - Kubernetes secret management
3. **Atlantis Secrets** - GitHub authentication for Atlantis

## Usage

```bash
# Initialize
terraform init

# Plan changes
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

## Configuration Files

- `providers.tf` - Provider configuration
- `main.tf` - Module declarations
- `variables.tf` - Variable definitions
- `outputs.tf` - Output declarations
- `terraform.auto.tfvars` - Auto-generated network config (DO NOT EDIT)
- `terraform.tfvars` - User-specific configuration (gitignored)

## Required Setup

1. Copy example tfvars:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit with your GitHub credentials:
   ```bash
   vim terraform.tfvars
   ```

3. Apply infrastructure:
   ```bash
   terraform apply
   ```

## Development Notes

This environment mirrors production but uses isolated network ranges for safe local testing.
