# =============================================================================
# ArgoCD Root ApplicationSet
# =============================================================================
# This ApplicationSet is the entry point for all GitOps-managed infrastructure.
# It dynamically selects the correct environment based on Terraform variables.
# =============================================================================

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
            path           = "k8s/apps/overlays/{{.environment}}"
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

  depends_on = [helm_release.this]
}
