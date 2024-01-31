provider "google" {
  project = var.project
  region  = var.region
}

data "google_client_config" "default" {}

provider "docker" {
  registry_auth {
    address  = "${var.region}-docker.pkg.dev"
    username = "oauth2accesstoken"
    password = data.google_client_config.default.access_token
  }
}

provider "local" {}

terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.0.2"
    }

    local = {
      source  = "hashicorp/local"
      version = "2.4.1"
    }
  }
}
