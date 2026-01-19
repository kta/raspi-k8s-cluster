# Kubernetes GitOps Structure

This directory contains all Kubernetes resources managed by ArgoCD following GitOps best practices.

## 🏗️ Architecture

```
k8s/
├── bootstrap/           # 🚀 Entry Points
│   ├── root.yaml        # ApplicationSet (environment-parameterized)
│   └── values/          # Environment parameters (production, vagrant)
│
├── apps/                # 📦 ArgoCD Application Definitions
│   ├── base/            # Common Application definitions
│   └── overlays/        # Environment-specific patches (production, vagrant)
│
└── infra/               # ☸️  Kubernetes Manifests
    ├── sealed-secrets/  # (Helm chart - no manifests)
    ├── cni/             # Pod networking (Flannel)
    ├── metallb/         # LoadBalancer implementation
    ├── cert-manager/    # TLS certificate automation
    ├── traefik/         # Ingress controller
    ├── argocd/          # ArgoCD UI ingress
    └── atlantis/        # Terraform PR automation
```

## 🚀 Quick Start

### Initial Setup

```bash
# Apply the root ApplicationSet (discovers all environments)
kubectl apply -f k8s/bootstrap/root.yaml
```

The ApplicationSet will:
1. Discover environment configs from `bootstrap/values/*.yaml`
2. Generate Applications for each environment (production, vagrant)
3. Deploy all infrastructure apps with proper ordering via sync-wave

### Deployment Order

Applications are deployed in the following order (via sync-wave annotations):

| Wave | Component | Purpose |
|------|-----------|---------|
| -9 | sealed-secrets | Secret encryption |
| -8 | cni | Pod networking |
| -7 | metallb | LoadBalancer |
| -6 | cert-manager | TLS certificates |
| -5 | cert-manager-resources | ClusterIssuers |
| -4 | traefik | Ingress controller |
| 0 | argocd-ingress | ArgoCD UI access |
| 1 | atlantis | Terraform automation |

## 📝 Design Principles

### 1. **No Number Prefixes** ❌ `01-`, `02-`
- **Problem**: Number prefixes are ugly and hard to maintain
- **Solution**: Use `sync-wave` annotations in Application metadata
- **Benefit**: Clean filenames, clear ordering in ArgoCD UI

### 2. **No Duplication** ❌ production/vagrant copies
- **Problem**: Identical files in multiple environments
- **Solution**: ApplicationSet with environment parameters + Kustomize overlays
- **Benefit**: Single source of truth, minimal environment differences

### 3. **Active infra/ Directory** ✅ Actual Kubernetes manifests
- **Problem**: `infra/` was underutilized
- **Solution**: `apps/` = ArgoCD definitions, `infra/` = Kubernetes resources
- **Benefit**: Clear separation, easier to navigate

## 🔧 Making Changes

### Adding a New Application

1. Create Application definition in `apps/base/`:
```yaml
# apps/base/my-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  source:
    repoURL: https://github.com/kta/raspi-k8s-cluster.git
    path: k8s/infra/my-app/overlays/production
  # ...
```

2. Add to `apps/base/kustomization.yaml`:
```yaml
resources:
  - my-app.yaml
```

3. Create manifests in `infra/my-app/`:
```
infra/my-app/
├── base/
│   ├── kustomization.yaml
│   └── deployment.yaml
└── overlays/
    ├── production/
    │   └── kustomization.yaml
    └── vagrant/
        └── kustomization.yaml
```

4. Patch environment differences in `apps/overlays/*/kustomization.yaml`

### Changing Environment Configuration

All environment differences are in:
- `bootstrap/values/*.yaml` - High-level parameters
- `apps/overlays/*/kustomization.yaml` - Application path patches
- `infra/*/overlays/*/kustomization.yaml` - Manifest value patches

**Example**: Change MetalLB IP range for vagrant:
```bash
vim k8s/infra/metallb/overlays/vagrant/kustomization.yaml
# Edit the IP range patch
git commit -am "Change vagrant MetalLB IP range"
git push
# ArgoCD auto-syncs
```

## 🌐 Environment Parameters

### Production (`bootstrap/values/production.yaml`)
- MetalLB: `192.168.1.200-192.168.1.220`
- Ingress IP: `192.168.1.200`
- ACME: Let's Encrypt Production

### Vagrant (`bootstrap/values/vagrant.yaml`)
- MetalLB: `192.168.56.200-192.168.56.220`
- Ingress IP: `192.168.56.200`
- ACME: Let's Encrypt Staging

## 📚 Additional Resources

- [ArgoCD App of Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [Kustomize Best Practices](https://kubectl.docs.kubernetes.io/guides/config_management/introduction/)
- [Sync Waves and Phases](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)

## 🆘 Troubleshooting

### Application stuck in "Progressing"
```bash
kubectl get app -n argocd my-app -o yaml | grep -A 10 status
# Check sync-wave order and dependencies
```

### Environment not discovered
```bash
# Check ApplicationSet generator
kubectl get appset -n argocd infra-root -o yaml
# Ensure bootstrap/values/*.yaml has correct format
```

### Wrong environment deployed
```bash
# Check which overlay is referenced
kubectl get app -n argocd infra-production -o yaml | grep path
```
