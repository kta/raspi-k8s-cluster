# my-app

Sample application demonstrating Pure Helm structure with ArgoCD and SealedSecrets.

## Overview

This Helm chart demonstrates the recommended structure for applications in this cluster:
- **Pure Helm** - No Kustomize, all configuration via Helm values
- **Environment-specific values** - Separate `values-prod.yaml` and `values-vagrant.yaml`
- **ArgoCD integration** - Sync-wave annotations for deployment ordering
- **SealedSecrets** - Encrypted secrets managed via values files

## Structure

```
my-app/
├── Chart.yaml                  # Helm chart metadata
├── values.yaml                 # Base values (shared across environments)
├── values-prod.yaml            # Production-specific values
├── values-vagrant.yaml         # Vagrant/development values
└── templates/
    ├── deployment.yaml         # Deployment with sync-wave annotation
    ├── service.yaml            # Service definition
    ├── sealed-secret.yaml      # SealedSecret template
    └── ...                     # Other standard templates
```

## Usage

### Local Testing

```bash
# Lint the chart
helm lint .

# Template with vagrant values
helm template my-app . -f values-vagrant.yaml

# Template with production values
helm template my-app . -f values-prod.yaml
```

### Deploying via ArgoCD

This chart is designed to be deployed via ArgoCD ApplicationSet. The ApplicationSet will:
1. Discover this chart in `k8s/applications/my-app/`
2. Select the appropriate values file based on environment (`values-{{.environment}}.yaml`)
3. Deploy with the configured sync-wave

### Managing Secrets

Secrets are managed using SealedSecrets. To encrypt a secret value:

```bash
# Generate encrypted value
echo -n "your-secret-value" | kubeseal --raw \
  --from-file=/dev/stdin \
  --namespace default \
  --name my-app

# Add the encrypted output to values-prod.yaml or values-vagrant.yaml
```

Example in `values-prod.yaml`:
```yaml
sealedSecret:
  enabled: true
  encryptedData:
    password: "AgBy3i4OJSWK+PiTySYZZA9rO43cGDEq..."
    api-key: "AgAR7bDj8fKLmNoPqRsTuVwXyZ..."
```

## Configuration

### Key Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `argocd.syncWave` | ArgoCD sync wave for deployment ordering | `"10"` |
| `replicaCount` | Number of replicas | `1` |
| `image.repository` | Container image repository | `nginx` |
| `image.tag` | Container image tag | `""` (uses appVersion) |
| `sealedSecret.enabled` | Enable SealedSecret creation | `false` |
| `sealedSecret.encryptedData` | Encrypted secret data | `{}` |

### Environment Differences

**Production (`values-prod.yaml`):**
- 2 replicas for high availability
- Higher resource limits
- Production-grade encrypted secrets

**Vagrant (`values-vagrant.yaml`):**
- 1 replica for resource efficiency
- Lower resource limits
- Development-friendly encrypted secrets

## ArgoCD Sync Wave

This application uses sync-wave `10` by default, which means it will be deployed after:
- Wave 0-3: Core infrastructure (CNI, MetalLB, etc.)
- Wave 4-9: Platform services (monitoring, ingress, etc.)

Adjust `argocd.syncWave` in values files if different ordering is needed.
