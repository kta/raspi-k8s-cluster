output "release_name" {
  value       = helm_release.this.name
  description = "Helm release name"
}

output "release_status" {
  value       = helm_release.this.status
  description = "Helm release status"
}

output "namespace" {
  value       = var.namespace
  description = "Namespace where Sealed Secrets is installed"
}

output "controller_name" {
  value       = var.fullname_override
  description = "Sealed Secrets controller name"
}
