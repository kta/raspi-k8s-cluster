# Sealed Secrets Module

Terraform module for deploying Sealed Secrets controller.

## Features

- Deploys Sealed Secrets via Helm chart
- Optimized resource limits for Raspberry Pi
- Configurable node placement and tolerations

## Usage

```hcl
module "sealed_secrets" {
  source = "../../modules/sealed-secrets"

  namespace = "kube-system"
  
  resources = {
    requests = {
      cpu    = "50m"
      memory = "64Mi"
    }
    limits = {
      cpu    = "200m"
      memory = "128Mi"
    }
  }
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| namespace | string | "kube-system" | Kubernetes namespace |
| release_name | string | "sealed-secrets" | Helm release name |
| chart_version | string | null | Chart version (null = latest) |
| fullname_override | string | "sealed-secrets-controller" | Full name override |
| resources | object | See defaults | Resource requests/limits |
| timeout | number | 300 | Helm timeout (seconds) |
| node_selector | map(string) | {} | Node selector |
| tolerations | list(any) | [] | Tolerations |

## Outputs

| Name | Description |
|------|-------------|
| release_name | Helm release name |
| release_status | Release status |
| namespace | Installation namespace |
| controller_name | Controller name |
