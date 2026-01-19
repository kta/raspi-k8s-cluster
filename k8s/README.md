# Kubernetes GitOps Structure

**最新構造（2026年1月リファクタリング v2）**

This directory contains all Kubernetes resources managed by ArgoCD following GitOps best practices.

## 🏗️ Architecture

```
k8s/
├── bootstrap/               # 🚀 Entry Points
│   ├── root.yaml            # ApplicationSet (Terraform managed)
│   └── values/              # Environment parameters (production, vagrant)
│
├── infrastructure/          # 🏗️  All Infrastructure
│   ├── argocd-apps/         # 📦 ArgoCD Application CRD Definitions
│   │   ├── base/            # Common Application definitions
│   │   └── overlays/        # Environment-specific patches
│   │
│   ├── sealed-secrets/      # ☸️  Kubernetes Manifests
│   ├── cni/                 # Pod networking (Flannel)
│   ├── metallb/             # LoadBalancer implementation
│   ├── cert-manager/        # TLS certificate automation
│   ├── traefik/             # Ingress controller
│   ├── argocd/              # ArgoCD UI ingress
│   └── atlantis/            # Terraform PR automation
│
└── applications/            # 🚢 User Applications (NEW!)
    ├── README.md            # Application deployment guide
    └── _example/            # Example app structure
```

## 🚀 Quick Start

### Initial Setup

```bash
# ⚠️ DO NOT apply root.yaml manually!
# It's managed by Terraform:
make terraform-apply ENV=vagrant  # or ENV=production

# Verify deployment
kubectl get appset -n argocd
kubectl get app -n argocd | grep infra-
```

The ApplicationSet will:
1. Discover environment configs from `bootstrap/values/*.yaml`
2. Generate Applications for each environment (production, vagrant)
3. Deploy all infrastructure apps with proper ordering via sync-wave

### Deployment Order

Applications are deployed in the following order (via sync-wave annotations):

| Wave | Component | Purpose | Location |
|------|-----------|---------|----------|
| -9 | sealed-secrets | Secret encryption | infrastructure/ |
| -8 | cni | Pod networking | infrastructure/ |
| -7 | metallb | LoadBalancer | infrastructure/ |
| -6 | cert-manager | TLS certificates | infrastructure/ |
| -6 | metallb-config | IP pool configuration | infrastructure/ |
| -5 | cert-manager-resources | ClusterIssuers | infrastructure/ |
| -4 | traefik | Ingress controller | infrastructure/ |
| -3 | traefik-middleware | Middleware config | infrastructure/ |
| 0 | argocd-ingress | ArgoCD UI access | infrastructure/ |
| 1 | atlantis | Terraform automation | infrastructure/ |
| 2 | atlantis-ingress | Atlantis webhook | infrastructure/ |
| **10+** | **User apps** | **Your applications** | **applications/** |

## 📝 Design Principles

### 1. **No Number Prefixes** ❌ `01-`, `02-`
- **Problem**: Number prefixes are ugly and hard to maintain
- **Solution**: Use `sync-wave` annotations in Application metadata
- **Benefit**: Clean filenames, clear ordering in ArgoCD UI

### 2. **No Duplication** ❌ production/vagrant copies
- **Problem**: Identical files in multiple environments
- **Solution**: ApplicationSet with environment parameters + Kustomize overlays
- **Benefit**: Single source of truth, minimal environment differences

### 3. **Infrastructure vs Applications** ✅ Clear separation
- **Problem**: Mixing infrastructure and user applications
- **Solution**: `infrastructure/` for infra, `applications/` for user apps
- **Benefit**: No confusion, clear responsibilities

### 4. **Better Naming** ✅ `argocd-apps/` directory
- **Problem**: `apps/` is ambiguous (ArgoCD Apps or user apps?)
- **Solution**: `argocd-apps/` clearly indicates ArgoCD Application CRDs
- **Benefit**: Self-documenting structure

## 🔧 Making Changes

### Adding Infrastructure Component

1. Create Application definition in `infrastructure/argocd-apps/base/`:
```yaml
# infrastructure/argocd-apps/base/my-component.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-component
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "10"
spec:
  source:
    repoURL: https://github.com/kta/raspi-k8s-cluster.git
    targetRevision: main
    path: k8s/infrastructure/my-component/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: my-component
  # ...
```

2. Add to `infrastructure/argocd-apps/base/kustomization.yaml`:
```yaml
resources:
  - my-component.yaml
```

3. Create manifests in `infrastructure/my-component/`:
```bash
mkdir -p infrastructure/my-component/{base,overlays/{production,vagrant}}
# Add your Kubernetes manifests
```

4. Add environment-specific patches in `infrastructure/argocd-apps/overlays/`:
```yaml
# infrastructure/argocd-apps/overlays/production/kustomization.yaml
patches:
  - target:
      kind: Application
      name: my-component
    patch: |-
      - op: replace
        path: /spec/source/path
        value: k8s/infrastructure/my-component/overlays/production
```

### Adding User Application

**See [applications/README.md](applications/README.md) for detailed guide!**

Quick example:
```bash
APP_NAME="my-app"
mkdir -p applications/${APP_NAME}/{base,overlays/{production,vagrant}}

# Create manifests (deployment, service, ingress, etc.)
vim applications/${APP_NAME}/base/kustomization.yaml

# Create ArgoCD Application definition
vim infrastructure/argocd-apps/base/${APP_NAME}.yaml

# Commit and deploy
git add . && git commit -m "Add ${APP_NAME}" && git push
```

### Changing Environment Values

1. Edit environment parameters:
```bash
# Change IPs, domains, etc.
vim bootstrap/values/production.yaml
vim bootstrap/values/vagrant.yaml
```

2. Edit Kustomize overlays for specific components:
```bash
# Example: Change MetalLB IP range
vim infrastructure/metallb/overlays/production/kustomization.yaml
```

3. Commit and push:
```bash
git add . && git commit -m "Update production IPs" && git push
```

ArgoCD will automatically sync the changes (if automated sync is enabled).

## 🌐 Environment Differences

Only these values differ between environments (everything else is identical):

| Component | Production | Vagrant |
|-----------|-----------|---------|
| MetalLB IP Range | 192.168.1.200-220 | 192.168.56.200-220 |
| Traefik LoadBalancer IP | 192.168.1.200 | 192.168.56.200 |
| Let's Encrypt ACME | Production | Staging |
| Domains | raspi.local | raspi.local |

## 🔍 Troubleshooting

### Application not syncing
```bash
# Check ApplicationSet
kubectl get appset -n argocd

# Check generated Applications
kubectl get app -n argocd

# Check specific app status
argocd app get infra-production

# Force sync
argocd app sync infra-production
```

### Wrong paths in Applications
Make sure your overlay patches are correct:
```bash
# Check overlay patches
cat infrastructure/argocd-apps/overlays/production/kustomization.yaml
```

### Environment not detected
Verify environment parameters file exists:
```bash
ls -la bootstrap/values/
# Should show: production.yaml, vagrant.yaml
```

## 📚 Learn More

- [STRUCTURE.md](STRUCTURE.md) - Complete directory structure reference
- [applications/README.md](applications/README.md) - User application deployment guide
- [ArgoCD ApplicationSet Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/)
- [Kustomize Documentation](https://kubectl.docs.kubernetes.io/references/kustomize/)
- [Project CLAUDE.md](/CLAUDE.md) - Full project documentation

## 🆕 What Changed in v2

### Before (v1):
```
k8s/
├── apps/          # ArgoCD Application CRDs
└── infra/         # Kubernetes manifests
```

### After (v2):
```
k8s/
├── infrastructure/        # All infrastructure
│   ├── argocd-apps/      # ArgoCD Application CRDs
│   ├── cni/              # Kubernetes manifests
│   └── ...
└── applications/         # User apps (NEW!)
```

### Migration Benefits:
✅ **No confusion**: Clear separation between infrastructure and user apps
✅ **Better naming**: `argocd-apps/` self-explanatory
✅ **Unified structure**: All infra in one place
✅ **Extensible**: Easy to add user apps without mixing with infra

---

**Note**: The `bootstrap/root.yaml` file is a **reference only**. The actual ApplicationSet is managed by Terraform. Use `make terraform-apply ENV=<environment>` to deploy.
