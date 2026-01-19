output "namespace" {
  value       = kubernetes_namespace_v1.this.metadata[0].name
  description = "ArgoCD namespace"
}

output "release_name" {
  value       = helm_release.this.name
  description = "Helm release name"
}

output "release_status" {
  value       = helm_release.this.status
  description = "Helm release status"
}

output "server_service_name" {
  value       = "${var.release_name}-server"
  description = "ArgoCD server service name"
}

output "initial_admin_password_command" {
  value       = "kubectl -n ${kubernetes_namespace_v1.this.metadata[0].name} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
  description = "Command to retrieve initial admin password"
}

output "port_forward_command" {
  value       = "kubectl port-forward svc/${var.release_name}-server -n ${kubernetes_namespace_v1.this.metadata[0].name} 8080:443"
  description = "Port forward command for ArgoCD UI"
}

output "environment_config" {
  value = {
    environment      = var.environment
    metallb_ip_range = var.metallb_ip_range
    ingress_ip       = var.ingress_ip
    vip              = var.vip
  }
  description = "Environment configuration"
}
