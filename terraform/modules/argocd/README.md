# ArgoCD Module

Terraform module for deploying ArgoCD on Kubernetes.

## Features

- Creates dedicated namespace with proper labels
- Deploys ArgoCD via Helm chart
- Manages environment configuration via ConfigMap
- Optimized for Raspberry Pi clusters

## Usage

```hcl
module "argocd" {
  source = "../../modules/argocd"

  namespace        = "argocd"
  chart_version    = "9.3.3"
  environment      = "production"
  metallb_ip_range = "192.168.1.200-192.168.1.220"
  ingress_ip       = "192.168.1.200"
  vip              = "192.168.1.100"
  enable_ha        = false
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| namespace | string | "argocd" | Kubernetes namespace |
| release_name | string | "argocd" | Helm release name |
| chart_version | string | "9.3.3" | Chart version |
| environment | string | - | Environment (production/vagrant) |
| metallb_ip_range | string | - | MetalLB IP range |
| ingress_ip | string | - | Ingress IP |
| vip | string | - | Virtual IP |
| enable_ha | bool | false | Enable HA mode |
| timeout | number | 900 | Helm timeout (seconds) |
| labels | map(string) | {} | Additional labels |

## Outputs

| Name | Description |
|------|-------------|
| namespace | ArgoCD namespace |
| release_name | Helm release name |
| server_service_name | Service name |
| initial_admin_password_command | Password retrieval command |
| port_forward_command | Port forward command |
| environment_config | Environment configuration |
