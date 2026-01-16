terraform {
  required_version = ">= 1.10.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.93.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0.1"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.5.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3.0"
    }
  }
}
