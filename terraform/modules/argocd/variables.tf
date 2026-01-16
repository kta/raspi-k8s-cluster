variable "argocd_version" {
  description = "ArgoCD Helm Chart バージョン"
  type        = string
  default     = "7.7.11"
}

variable "argocd_namespace" {
  description = "ArgoCD Namespace"
  type        = string
  default     = "argocd"
}
