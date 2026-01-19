# ArgoCD Outputs
output "argocd_namespace" {
  value       = module.argocd.namespace
  description = "ArgoCD namespace"
}

output "argocd_server_service" {
  value       = module.argocd.server_service_name
  description = "ArgoCD server service name"
}

output "argocd_initial_admin_password_command" {
  value       = module.argocd.initial_admin_password_command
  description = "Command to retrieve ArgoCD initial admin password"
}

output "argocd_port_forward_command" {
  value       = module.argocd.port_forward_command
  description = "ArgoCD UI port forward command"
}

output "argocd_environment_config" {
  value       = module.argocd.environment_config
  description = "ArgoCD environment configuration"
}

# Sealed Secrets Outputs
output "sealed_secrets_namespace" {
  value       = module.sealed_secrets.namespace
  description = "Sealed Secrets namespace"
}

output "sealed_secrets_controller" {
  value       = module.sealed_secrets.controller_name
  description = "Sealed Secrets controller name"
}

# Atlantis Outputs
output "atlantis_namespace" {
  value       = module.atlantis_secrets.namespace
  description = "Atlantis namespace"
}

output "atlantis_secret_name" {
  value       = module.atlantis_secrets.secret_name
  description = "Atlantis GitHub secret name"
}

# Summary
output "deployment_summary" {
  value = {
    environment      = var.environment
    argocd_namespace = module.argocd.namespace
    argocd_status    = module.argocd.release_status
    sealed_secrets   = module.sealed_secrets.release_status
    atlantis_ready   = module.atlantis_secrets.namespace
  }
  description = "Deployment summary"
}
