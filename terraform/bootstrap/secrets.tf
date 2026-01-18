# ArgoCD がプライベートリポジトリにアクセスするための認証情報
resource "kubernetes_secret" "argocd_repo_creds" {
  metadata {
    name      = "repo-creds"
    namespace = kubernetes_namespace.argocd.metadata[0].name

    labels = {
      "argocd.argoproj.io/secret-type" = "repo-creds"
    }
  }

  data = {
    type     = "git"
    url      = "https://github.com"
    username = var.github_username
    password = var.github_token
  }

  type = "Opaque"

  depends_on = [helm_release.argocd]
}

# Atlantis 用の GitHub Secret（Atlantis デプロイ時に使用）
resource "kubernetes_namespace" "atlantis" {
  metadata {
    name = "atlantis"

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_secret" "atlantis_github" {
  metadata {
    name      = "atlantis-github-secret"
    namespace = kubernetes_namespace.atlantis.metadata[0].name
  }

  data = {
    token = var.github_token
  }

  type = "Opaque"
}