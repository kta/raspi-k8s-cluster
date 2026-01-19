# Atlantis Secrets Module

Terraform module for managing Atlantis GitHub credentials.

## Features

- Creates dedicated namespace
- Manages GitHub token as Kubernetes secret
- Proper labeling for GitOps tracking

## Usage

```hcl
module "atlantis_secrets" {
  source = "../../modules/atlantis-secrets"

  namespace    = "atlantis"
  github_token = var.github_token
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| namespace | string | "atlantis" | Kubernetes namespace |
| secret_name | string | "atlantis-github-secret" | Secret name |
| github_token | string (sensitive) | - | GitHub PAT |
| labels | map(string) | {} | Additional labels |

## Outputs

| Name | Description |
|------|-------------|
| namespace | Atlantis namespace |
| secret_name | GitHub secret name |
