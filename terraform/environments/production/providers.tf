terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3."
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }

  # Uncomment to use remote backend
  # backend "s3" {
  #   bucket = "raspi-k8s-terraform-state"
  #   key    = "production/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}
