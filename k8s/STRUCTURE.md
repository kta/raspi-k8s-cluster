# k8s Directory Structure Reference

## 📁 Complete Directory Tree

```
k8s/
├── 📖 README.md                      # Main documentation
├── 📖 MIGRATION.md                   # Migration guide from old structure
├── 📖 STRUCTURE.md                   # This file
│
├── 🚀 bootstrap/                     # Entry Points
│   ├── root.yaml                     # ⭐ Main entry: ApplicationSet
│   ├── production.yaml               # Legacy: direct production bootstrap
│   ├── vagrant.yaml                  # Legacy: direct vagrant bootstrap
│   └── values/                       # Environment parameters
│       ├── production.yaml           # Production config (IPs, domains, etc.)
│       └── vagrant.yaml              # Vagrant config
│
├── 📦 apps/                          # ArgoCD Application Definitions
│   ├── base/                         # Common Application definitions
│   │   ├── kustomization.yaml        # Aggregates all apps
│   │   ├── sealed-secrets.yaml       # Wave -9: Secret encryption
│   │   ├── cni.yaml                  # Wave -8: Pod networking
│   │   ├── metallb.yaml              # Wave -7,-6: LoadBalancer
│   │   ├── cert-manager.yaml         # Wave -6: TLS automation
│   │   ├── cert-manager-resources.yaml # Wave -5: ClusterIssuers
│   │   ├── traefik.yaml              # Wave -4,-3: Ingress controller
│   │   ├── argocd-ingress.yaml       # Wave 0: ArgoCD UI
│   │   └── atlantis.yaml             # Wave 1,2: Terraform automation
│   └── overlays/                     # Environment-specific patches
│       ├── production/
│       │   └── kustomization.yaml    # Patches for production paths/IPs
│       └── vagrant/
│           └── kustomization.yaml    # Patches for vagrant paths/IPs
│
├── ☸️  infra/                        # Kubernetes Manifests (actual resources)
│   │
│   ├── sealed-secrets/               # (Empty - deployed via Helm chart)
│   │
│   ├── cni/                          # Flannel CNI
│   │   ├── base/
│   │   │   ├── kustomization.yaml
│   │   │   └── kube-flannel.yml      # Flannel DaemonSet
│   │   └── overlays/
│   │       ├── production/
│   │       └── vagrant/
│   │
│   ├── metallb/                      # LoadBalancer
│   │   ├── base/
│   │   │   ├── kustomization.yaml
│   │   │   └── ip-pool.yaml          # IPAddressPool + L2Advertisement
│   │   └── overlays/
│   │       ├── production/
│   │       │   └── kustomization.yaml  # IP: 192.168.1.200-220
│   │       └── vagrant/
│   │           └── kustomization.yaml  # IP: 192.168.56.200-220
│   │
│   ├── cert-manager/                 # TLS Certificate Management
│   │   ├── base/
│   │   │   ├── kustomization.yaml
│   │   │   └── cluster-issuer.yaml   # Let's Encrypt ClusterIssuer
│   │   └── overlays/
│   │       ├── production/
│   │       │   └── kustomization.yaml  # ACME: production
│   │       └── vagrant/
│   │           └── kustomization.yaml  # ACME: staging
│   │
│   ├── traefik/                      # Ingress Controller
│   │   ├── base/
│   │   │   ├── kustomization.yaml
│   │   │   └── middleware.yaml       # HTTPS redirect middleware
│   │   └── overlays/
│   │       ├── production/
│   │       └── vagrant/
│   │
│   ├── argocd/                       # ArgoCD UI Access
│   │   ├── base/
│   │   │   ├── kustomization.yaml
│   │   │   └── ingress.yaml          # ArgoCD UI Ingress
│   │   └── overlays/
│   │       ├── production/
│   │       │   └── kustomization.yaml  # Host: argocd.raspi.local
│   │       └── vagrant/
│   │           └── kustomization.yaml  # Host: argocd.raspi.local
│   │
│   └── atlantis/                     # Terraform PR Automation
│       ├── base/
│       │   ├── kustomization.yaml
│       │   └── ingress.yaml          # Atlantis webhook Ingress
│       └── overlays/
│           ├── production/
│           │   └── kustomization.yaml  # Host: atlantis.raspi.local
│           └── vagrant/
│               └── kustomization.yaml  # Host: atlantis.raspi.local
│
└── 🔐 secrets/                       # Sealed Secrets (encrypted)
    ├── argocd/
    └── atlantis/
        └── github-token.yaml         # GitHub PAT (sealed)
```

## 🎯 Key Files

| File | Purpose | When to Edit |
|------|---------|--------------|
| `bootstrap/root.yaml` | Main entry point (ApplicationSet) | Add new environment |
| `bootstrap/values/*.yaml` | Environment parameters | Change IPs, domains |
| `apps/base/kustomization.yaml` | List of all apps | Add new application |
| `apps/base/*.yaml` | Application definitions | Add new component |
| `apps/overlays/*/kustomization.yaml` | Environment patches | Change app paths |
| `infra/*/base/*.yaml` | K8s manifests | Add new resources |
| `infra/*/overlays/*/kustomization.yaml` | Value patches | Change IPs, domains |

## 🔄 Data Flow

```
User applies bootstrap/root.yaml
  ↓
ApplicationSet discovers bootstrap/values/*.yaml
  ↓
Generates Applications (infra-production, infra-vagrant)
  ↓
Each Application points to apps/overlays/{env}
  ↓
Kustomize merges apps/base + apps/overlays/{env}
  ↓
Result: Applications with environment-specific paths
  ↓
Applications point to infra/{component}/overlays/{env}
  ↓
Kustomize merges infra/{component}/base + overlays/{env}
  ↓
Result: K8s resources with environment-specific values
  ↓
ArgoCD deploys in sync-wave order
```

## 📊 Sync Wave Order

| Wave | Components | Notes |
|------|-----------|-------|
| -9 | sealed-secrets | Must be first for secret decryption |
| -8 | cni | Network before everything |
| -7 | metallb | LoadBalancer controller |
| -6 | cert-manager, metallb-config | Certificate automation + IP pool |
| -5 | cert-manager-resources | ClusterIssuers |
| -4 | traefik | Ingress controller |
| -3 | traefik-middleware | Middleware configuration |
| 0 | argocd-ingress | ArgoCD UI access |
| 1 | atlantis | Terraform automation |
| 2 | atlantis-ingress | Atlantis webhook |

## 🌐 Environment Differences

Only these values differ between production and vagrant:

| Component | Production | Vagrant |
|-----------|-----------|---------|
| MetalLB IP Range | 192.168.1.200-220 | 192.168.56.200-220 |
| Traefik LoadBalancer IP | 192.168.1.200 | 192.168.56.200 |
| Let's Encrypt ACME | Production | Staging |
| Domain | raspi.local | raspi.local |

Everything else is identical across environments.

## 🧹 Archived Files

Old structure moved to `.archived/`:
- `envs/production/*.yaml` - Old numbered Application files
- `envs/vagrant/*.yaml` - Old numbered Application files

Can be safely deleted after migration verification.

## 📚 Learn More

- [README.md](README.md) - Usage and quick start
- [MIGRATION.md](MIGRATION.md) - Migration guide
- [ArgoCD Docs](https://argo-cd.readthedocs.io/)
- [Kustomize Docs](https://kubectl.docs.kubernetes.io/)
