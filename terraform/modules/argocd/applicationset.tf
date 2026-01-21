# =============================================================================
# ArgoCD Root ApplicationSet
# =============================================================================
# This ApplicationSet is the entry point for all GitOps-managed infrastructure.
# It dynamically selects the correct environment based on Terraform variables.
# =============================================================================

# Wait for ArgoCD CRDs to be available
resource "null_resource" "wait_for_argocd_crds" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for ArgoCD CRDs to be available..."
      for i in {1..30}; do
        if kubectl get crd applicationsets.argoproj.io > /dev/null 2>&1; then
          echo "ArgoCD CRDs are available"
          exit 0
        fi
        echo "Waiting for CRDs... ($i/30)"
        sleep 10
      done
      echo "Timeout waiting for ArgoCD CRDs"
      exit 1
    EOT
  }

  depends_on = [helm_release.this]
}

resource "kubernetes_manifest" "root_applicationset" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "ApplicationSet"

    metadata = {
      name      = "infra-root"
      namespace = kubernetes_namespace_v1.this.metadata[0].name

      labels = {
        "app.kubernetes.io/name"       = "argocd"
        "app.kubernetes.io/component"  = "applicationset"
        "app.kubernetes.io/managed-by" = "terraform"
      }
    }

    spec = {
      goTemplate        = true
      goTemplateOptions = ["missingkey=error"]

      generators = [
        {
          git = {
            repoURL  = var.git_repo_url
            revision = var.git_revision
            files = [
              {
                path = "k8s/bootstrap/values/${var.environment}.yaml"
              }
            ]
          }
        }
      ]

      template = {
        metadata = {
          name      = "infra-{{.environment}}"
          namespace = kubernetes_namespace_v1.this.metadata[0].name

          labels = {
            "app.kubernetes.io/instance" = "root"
            "app.kubernetes.io/part-of"  = "infra"
            "environment"                = "{{.environment}}"
          }

          finalizers = [
            "resources-finalizer.argocd.argoproj.io"
          ]
        }

        spec = {
          project = "default"

          source = {
            repoURL        = var.git_repo_url
            targetRevision = var.git_revision
            path           = "k8s/infrastructure/00-argocd-apps/argocd-apps/overlays/{{.environment}}"
          }

          destination = {
            server    = "https://kubernetes.default.svc"
            namespace = kubernetes_namespace_v1.this.metadata[0].name
          }

          syncPolicy = {
            automated = {
              prune    = true
              selfHeal = true
            }

            syncOptions = [
              "CreateNamespace=true"
            ]

            retry = {
              limit = 5
              backoff = {
                duration    = "5s"
                factor      = 2
                maxDuration = "3m"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.this,
    kubernetes_config_map_v1.environment_config,
    null_resource.wait_for_argocd_crds
  ]

  # Wait for ArgoCD CRDs to be available
  computed_fields = ["metadata.annotations"]
}
