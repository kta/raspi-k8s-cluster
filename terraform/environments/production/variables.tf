# General
variable "environment" {
  type        = string
  default     = "production"
  description = "Environment name"

  validation {
    condition     = contains(["production", "vagrant"], var.environment)
    error_message = "Environment must be 'production' or 'vagrant'"
  }
}

variable "kubeconfig_path" {
  type        = string
  default     = "~/.kube/config"
  description = "Path to kubeconfig file"
}

# ArgoCD
variable "argocd_namespace" {
  type        = string
  default     = "argocd"
  description = "ArgoCD namespace"
}

variable "argocd_chart_version" {
  type        = string
  default     = "9.3.3"
  description = "ArgoCD Helm chart version"
}

variable "enable_ha" {
  type        = bool
  default     = false
  description = "Enable ArgoCD high availability mode"
}

# Network Configuration
variable "metallb_ip_range" {
  type        = string
  description = "MetalLB IP address pool range (e.g., 192.168.1.200-192.168.1.220)"
}

variable "ingress_ip" {
  type        = string
  description = "Ingress LoadBalancer IP address"
}

variable "vip" {
  type        = string
  description = "Keepalived virtual IP address"
}

# Sealed Secrets
variable "sealed_secrets_namespace" {
  type        = string
  default     = "kube-system"
  description = "Sealed Secrets namespace"
}

variable "sealed_secrets_chart_version" {
  type        = string
  default     = null
  description = "Sealed Secrets chart version (null = latest)"
}

variable "sealed_secrets_resources" {
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "50m"
      memory = "64Mi"
    }
    limits = {
      cpu    = "200m"
      memory = "128Mi"
    }
  }
  description = "Sealed Secrets resource limits"
}

# Atlantis
variable "atlantis_namespace" {
  type        = string
  default     = "atlantis"
  description = "Atlantis namespace"
}

# GitHub
variable "github_token" {
  type        = string
  sensitive   = true
  description = "GitHub Personal Access Token"
}

variable "github_username" {
  type        = string
  description = "GitHub username"
}

variable "github_repo_url" {
  type        = string
  description = "GitOps repository URL"
}

variable "git_revision" {
  type        = string
  default     = "main"
  description = "Git branch/revision for ArgoCD ApplicationSet"
}

# Helm
variable "helm_timeout" {
  type        = number
  default     = 900
  description = "Helm release timeout in seconds"
}
