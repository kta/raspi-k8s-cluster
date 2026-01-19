variable "namespace" {
  type        = string
  default     = "atlantis"
  description = "Kubernetes namespace for Atlantis"
}

variable "secret_name" {
  type        = string
  default     = "atlantis-github-secret"
  description = "Name of the Kubernetes secret"
}

variable "github_token" {
  type        = string
  sensitive   = true
  description = "GitHub Personal Access Token"
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Additional labels for resources"
}
