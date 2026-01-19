variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Kubernetes namespace for Sealed Secrets"
}

variable "release_name" {
  type        = string
  default     = "sealed-secrets"
  description = "Helm release name"
}

variable "chart_version" {
  type        = string
  default     = null
  description = "Sealed Secrets Helm chart version (null = latest)"
}

variable "fullname_override" {
  type        = string
  default     = "sealed-secrets-controller"
  description = "Override the full name of the release"
}

variable "resources" {
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
  description = "Resource requests and limits"
}

variable "timeout" {
  type        = number
  default     = 300
  description = "Helm release timeout in seconds"
}

variable "node_selector" {
  type        = map(string)
  default     = {}
  description = "Node selector for pod placement"
}

variable "tolerations" {
  type        = list(any)
  default     = []
  description = "Tolerations for pod scheduling"
}
