# k8s Directory Structure Reference

**最新構造（2026年1月リファクタリング v2）**

## 📁 Complete Directory Tree

```
k8s/
├── 📖 README.md                      # Main documentation
├── 📖 STRUCTURE.md                   # This file
│
├── 🚀 bootstrap/                     # Entry Points
│   ├── root.yaml                     # ⭐ Main entry: ApplicationSet (Terraform managed)
│   └── values/                       # Environment parameters
│       ├── production.yaml           # Production config (IPs, domains, etc.)
│       └── vagrant.yaml              # Vagrant config
│
├── 🏗️  infrastructure/               # All Infrastructure (Apps + Manifests)
│   │
│   ├── 📦 argocd-apps/               # ArgoCD Application CRD Definitions
│   │   ├── base/                     # Common Application definitions
│   │   │   ├── kustomization.yaml    # Aggregates all apps
│   │   │   ├── sealed-secrets.yaml   # Wave -9: Secret encryption
│   │   │   ├── cni.yaml              # Wave -8: Pod networking
│   │   │   ├── metallb.yaml          # Wave -7,-6: LoadBalancer
│   │   │   ├── cert-manager.yaml     # Wave -6: TLS automation
│   │   │   ├── cert-manager-resources.yaml # Wave -5: ClusterIssuers
│   │   │   ├── traefik.yaml          # Wave -4,-3: Ingress controller
│   │   │   ├── argocd-ingress.yaml   # Wave 0: ArgoCD UI
│   │   │   └── atlantis.yaml         # Wave 1,2: Terraform automation
│   │   └── overlays/                 # Environment-specific patches
│   │       ├── production/
│   │       │   └── kustomization.yaml  # Patches for production paths/IPs
│   │       └── vagrant/
│   │           └── kustomization.yaml  # Patches for vagrant paths/IPs
│   │
│   ├── ☸️  sealed-secrets/           # (Empty - deployed via Helm chart)
│   │
│   ├── ☸️  cni/                      # Flannel CNI
│   │   ├── base/
│   │   │   ├── kustomization.yaml
│   │   │   └── kube-flannel.yml      # Flannel DaemonSet
│   │   └── overlays/
│   │       ├── production/
│   │       └── vagrant/
│   │
│   ├── ☸️  metallb/                  # LoadBalancer
│   │   ├── base/
│   │   │   ├── kustomization.yaml
│   │   │   └── ip-pool.yaml          # IPAddressPool + L2Advertisement
│   │   └── overlays/
│   │       ├── production/
│   │       │   └── kustomization.yaml  # IP: 192.168.1.200-220
│   │       └── vagrant/
│   │           └── kustomization.yaml  # IP: 192.168.56.200-220
│   │
│   ├── ☸️  cert-manager/             # TLS Certificate Management
│   │   ├── base/
│   │   │   ├── kustomization.yaml
│   │   │   └── cluster-issuer.yaml   # Let's Encrypt ClusterIssuer
│   │   └── overlays/
│   │       ├── production/
│   │       │   └── kustomization.yaml  # ACME: production
│   │       └── vagrant/
│   │           └── kustomization.yaml  # ACME: staging
│   │
│   ├── ☸️  traefik/                  # Ingress Controller
│   │   ├── base/
│   │   │   ├── kustomization.yaml
│   │   │   └── middleware.yaml       # HTTPS redirect middleware
│   │   └── overlays/
│   │       ├── production/
│   │       └── vagrant/
│   │
│   ├── ☸️  argocd/                   # ArgoCD UI Access
│   │   ├── base/
│   │   │   ├── kustomization.yaml
│   │   │   └── ingress.yaml          # ArgoCD UI Ingress
│   │   └── overlays/
│   │       ├── production/
│   │       │   └── kustomization.yaml  # Host: argocd.raspi.local
│   │       └── vagrant/
│   │           └── kustomization.yaml  # Host: argocd.raspi.local
│   │
│   └── ☸️  atlantis/                 # Terraform PR Automation
│       ├── base/
│       │   ├── kustomization.yaml
│       │   └── ingress.yaml          # Atlantis webhook Ingress
│       └── overlays/
│           ├── production/
│           │   └── kustomization.yaml  # Host: atlantis.raspi.local
│           └── vagrant/
│               └── kustomization.yaml  # Host: atlantis.raspi.local
│
├── 🚢 applications/                  # User Applications (NEW!)
│   ├── README.md                     # Application deployment guide
│   └── _example/                     # Example application structure
│       ├── base/
│       │   ├── kustomization.yaml
│       │   ├── deployment.yaml
│       │   ├── service.yaml
│       │   └── ingress.yaml
│       └── overlays/
│           ├── production/
│           │   └── kustomization.yaml
│           └── vagrant/
│               └── kustomization.yaml
│
└── 🔐 secrets/                       # Sealed Secrets (encrypted)
    ├── argocd/
    └── atlantis/
        └── github-token.yaml         # GitHub PAT (sealed)
```

## 🎯 Key Files

| File | Purpose | When to Edit |
|------|---------|--------------|
| `bootstrap/root.yaml` | Main entry point (ApplicationSet) | ⚠️ Terraform managed - reference only |
| `bootstrap/values/*.yaml` | Environment parameters | Change IPs, domains |
| `infrastructure/argocd-apps/base/kustomization.yaml` | List of all infra apps | Add new infrastructure component |
| `infrastructure/argocd-apps/base/*.yaml` | Application definitions | Add new infra component |
| `infrastructure/argocd-apps/overlays/*/kustomization.yaml` | Environment patches | Change app paths |
| `infrastructure/*/base/*.yaml` | K8s manifests | Add new resources |
| `infrastructure/*/overlays/*/kustomization.yaml` | Value patches | Change IPs, domains |
| `applications/README.md` | User app guide | Learn how to deploy apps |
| `applications/your-app/` | Your application | Deploy custom apps |

## 🔄 Data Flow

```
Terraform applies ApplicationSet
  ↓
ApplicationSet discovers bootstrap/values/*.yaml
  ↓
Generates Applications (infra-production, infra-vagrant)
  ↓
Each Application points to infrastructure/argocd-apps/overlays/{env}
  ↓
Kustomize merges infrastructure/argocd-apps/base + overlays/{env}
  ↓
Result: Applications with environment-specific paths
  ↓
Applications point to infrastructure/{component}/overlays/{env}
  ↓
Kustomize merges infrastructure/{component}/base + overlays/{env}
  ↓
Result: K8s resources with environment-specific values
  ↓
ArgoCD deploys in sync-wave order
```

## 📊 Sync Wave Order

| Wave | Components | Location | Notes |
|------|-----------|----------|-------|
| -9 | sealed-secrets | infrastructure/ | Must be first for secret decryption |
| -8 | cni | infrastructure/ | Network before everything |
| -7 | metallb | infrastructure/ | LoadBalancer controller |
| -6 | cert-manager, metallb-config | infrastructure/ | Certificate automation + IP pool |
| -5 | cert-manager-resources | infrastructure/ | ClusterIssuers |
| -4 | traefik | infrastructure/ | Ingress controller |
| -3 | traefik-middleware | infrastructure/ | Middleware configuration |
| 0 | argocd-ingress | infrastructure/ | ArgoCD UI access |
| 1 | atlantis | infrastructure/ | Terraform automation |
| 2 | atlantis-ingress | infrastructure/ | Atlantis webhook |
| **10+** | **User apps** | **applications/** | **Your custom applications** |

## 🌐 Environment Differences

Only these values differ between production and vagrant:

| Component | Production | Vagrant |
|-----------|-----------|---------|
| MetalLB IP Range | 192.168.1.200-220 | 192.168.56.200-220 |
| Traefik LoadBalancer IP | 192.168.1.200 | 192.168.56.200 |
| Let's Encrypt ACME | Production | Staging |
| Domain | raspi.local | raspi.local |

Everything else is identical across environments.

## 🆕 What Changed in v2 Refactoring

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
│   ├── metallb/
│   └── ...
└── applications/         # User apps (NEW!)
```

### Benefits:
✅ **Clear separation**: Infrastructure vs User applications
✅ **Better naming**: `argocd-apps/` clarifies these are Application CRDs
✅ **Unified infrastructure**: All infra components in one place
✅ **Extensibility**: Easy to add new user apps in `applications/`
✅ **No confusion**: Users won't mix infra with their apps

## 📚 Learn More

- [README.md](README.md) - Usage and quick start
- [applications/README.md](applications/README.md) - How to deploy your apps
- [ArgoCD Docs](https://argo-cd.readthedocs.io/)
- [Kustomize Docs](https://kubectl.docs.kubernetes.io/)
- [CLAUDE.md](/CLAUDE.md) - Full project documentation
