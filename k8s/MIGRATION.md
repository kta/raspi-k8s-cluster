# Migration Guide: Old → New k8s Structure

## 🎯 Changes Summary

| Aspect | Old | New | Benefit |
|--------|-----|-----|---------|
| **Ordering** | `01-`, `02-` prefixes | sync-wave annotations | Clean filenames |
| **Environments** | Duplicated files | Kustomize overlays | DRY principle |
| **Structure** | Flat `envs/` | Layered `apps/` + `infra/` | Clear separation |
| **Entry Point** | Per-env bootstrap | ApplicationSet | Single entry |

## 📋 Migration Steps

### Step 1: Understand New Structure

```
k8s/
├── bootstrap/root.yaml          # Single entry point (ApplicationSet)
├── apps/                         # ArgoCD Application definitions
│   ├── base/                     # Common definitions (no env diffs)
│   └── overlays/{env}/           # Environment-specific patches
└── infra/                        # Actual Kubernetes manifests
    └── {component}/
        ├── base/                 # Common manifests
        └── overlays/{env}/       # Environment-specific values
```

### Step 2: Apply New Bootstrap

```bash
# Review the new ApplicationSet
cat k8s/bootstrap/root.yaml

# Apply it (this will create infra-production and infra-vagrant apps)
kubectl apply -f k8s/bootstrap/root.yaml

# Verify ApplicationSet created both environments
kubectl get appset -n argocd
kubectl get app -n argocd | grep infra-
```

### Step 3: Verify Applications

```bash
# All applications should be synced
kubectl get app -n argocd

# Check sync waves are working
kubectl get app -n argocd -o json | jq -r '.items[] | "\(.metadata.annotations["argocd.argoproj.io/sync-wave"] // "0") \(.metadata.name)"' | sort -n

# Expected order:
# -9 sealed-secrets
# -8 cni
# -7 metallb
# -6 cert-manager, metallb-config
# -5 cert-manager-resources
# -4 traefik
# -3 traefik-middleware
#  0 argocd-ingress
#  1 atlantis
#  2 atlantis-ingress
```

### Step 4: Delete Old Bootstrap (if using)

```bash
# Only if you previously used the old per-environment bootstrap
kubectl delete -f k8s/bootstrap/production.yaml
kubectl delete -f k8s/bootstrap/vagrant.yaml
```

### Step 5: Clean Up Old Files (optional)

```bash
# After verifying everything works for a week or two
rm -rf k8s/.archived/
```

## 🔍 Comparison Examples

### Example 1: MetalLB IP Range

**Old Structure** (duplicated):
```
envs/production/03-metallb.yaml:    path: k8s/infra/metallb/overlays/production
envs/vagrant/03-metallb.yaml:       path: k8s/infra/metallb/overlays/vagrant
```

**New Structure** (single source + overlay):
```
apps/base/metallb.yaml:                        # Single definition
apps/overlays/production/kustomization.yaml:   # Patches path to production
apps/overlays/vagrant/kustomization.yaml:      # Patches path to vagrant

infra/metallb/overlays/production/kustomization.yaml:  # IP range: 192.168.1.x
infra/metallb/overlays/vagrant/kustomization.yaml:     # IP range: 192.168.56.x
```

### Example 2: Ordering

**Old Structure**:
```
01-sealed-secrets.yaml
02-cni.yaml
03-metallb.yaml
...
```

**New Structure**:
```
apps/base/kustomization.yaml:
  resources:
    - sealed-secrets.yaml    # sync-wave: -9
    - cni.yaml               # sync-wave: -8
    - metallb.yaml           # sync-wave: -7
```

## ⚙️ How It Works

### ApplicationSet Discovery

The root ApplicationSet uses a Git generator:

```yaml
generators:
  - git:
      files:
        - path: "k8s/bootstrap/values/*.yaml"
```

This discovers:
- `bootstrap/values/production.yaml` → Creates `infra-production` App
- `bootstrap/values/vagrant.yaml` → Creates `infra-vagrant` App

### Kustomize Overlays

Each environment overlay patches the base Applications:

```yaml
# apps/overlays/production/kustomization.yaml
patches:
  - target:
      name: metallb-config
    patch: |-
      - op: replace
        path: /spec/source/path
        value: k8s/infra/metallb/overlays/production
```

This changes the path from base to production-specific.

### Sync Waves

Applications deploy in order:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-9"
```

Lower numbers deploy first. This ensures dependencies (CNI before MetalLB, etc.).

## �� Rollback Plan

If something goes wrong:

```bash
# Delete new ApplicationSet
kubectl delete -f k8s/bootstrap/root.yaml

# Reapply old bootstrap
kubectl apply -f k8s/.archived/envs/production/

# Or reapply legacy bootstrap
kubectl apply -f k8s/bootstrap/production.yaml
```

Old files are preserved in `k8s/.archived/` for this purpose.

## 📚 References

- [ArgoCD ApplicationSets](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [Kustomize Overlays](https://kubectl.docs.kubernetes.io/references/kustomize/glossary/#overlay)
- [Sync Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
