module "argocd" {
  source = "../../modules/argocd"

  namespace        = var.argocd_namespace
  chart_version    = var.argocd_chart_version
  environment      = var.environment
  metallb_ip_range = var.metallb_ip_range
  ingress_ip       = var.ingress_ip
  vip              = var.vip
  enable_ha        = var.enable_ha
  timeout          = var.helm_timeout
  git_repo_url     = var.github_repo_url
  git_revision     = var.git_revision

  labels = {
    environment = var.environment
  }
}

module "sealed_secrets" {
  source = "../../modules/sealed-secrets"

  namespace     = var.sealed_secrets_namespace
  chart_version = var.sealed_secrets_chart_version
  timeout       = var.helm_timeout

  resources = var.sealed_secrets_resources
}

module "atlantis_secrets" {
  source = "../../modules/atlantis-secrets"

  namespace    = var.atlantis_namespace
  github_token = var.github_token

  labels = {
    environment = var.environment
  }
}
