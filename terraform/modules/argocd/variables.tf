variable "namespace" {
  type        = string
  default     = "argocd"
  description = "Kubernetes namespace for ArgoCD"
}

variable "release_name" {
  type        = string
  default     = "argocd"
  description = "Helm release name"
}

variable "chart_version" {
  type        = string
  default     = "9.3.3"
  description = "ArgoCD Helm chart version"
}

variable "environment" {
  type        = string
  description = "Environment name (production or vagrant)"

  validation {
    condition     = contains(["production", "vagrant"], var.environment)
    error_message = "Environment must be 'production' or 'vagrant'"
  }
}

variable "metallb_ip_range" {
  type        = string
  description = "MetalLB IP address pool range"
}

variable "ingress_ip" {
  type        = string
  description = "Ingress LoadBalancer IP address"
}

variable "vip" {
  type        = string
  description = "Keepalived virtual IP address"
}

variable "enable_ha" {
  type        = bool
  default     = false
  description = "Enable high availability mode"
}

variable "timeout" {
  type        = number
  default     = 900
  description = "Helm release timeout in seconds"
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Additional labels for resources"
}

variable "git_repo_url" {
  type        = string
  default     = "https://github.com/kta/raspi-k8s-cluster.git"
  description = "Git repository URL for ArgoCD applications"
}

variable "git_revision" {
  type        = string
  default     = "main"
  description = "Git revision/branch for ArgoCD applications"
}
