output "namespace" {
  value       = kubernetes_namespace_v1.this.metadata[0].name
  description = "Atlantis namespace"
}

output "secret_name" {
  value       = kubernetes_secret_v1.github.metadata[0].name
  description = "GitHub secret name"
}
