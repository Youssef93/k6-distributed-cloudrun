
locals {
  docker-image = "${var.region}-docker.pkg.dev/${var.project}/${google_artifact_registry_repository.k6.name}/k6"
  database-url = "postgresql://${var.DATABASE_USER}:${var.DATABASE_PASSWORD}@${google_compute_instance.k6.network_interface[0].access_config[0].nat_ip}/${var.DATABASE_NAME}"
}

resource "google_artifact_registry_repository" "k6" {
  location      = var.region
  repository_id = "k6"
  description   = "K6 docker image artofact registry"
  format        = "DOCKER"
}

resource "docker_image" "k6" {
  name = local.docker-image
  build {
    context = "${path.cwd}/k6-docker-image"
    # Only needed if you run terraform plan from a macos machine
    platform = var.docker-platform
  }
  triggers = {
    dir_sha1 = sha1(join("", [for f in fileset("${path.cwd}/k6-docker-image", "**") : filesha1("${path.cwd}/k6-docker-image/${f}")]))
  }
}

resource "docker_registry_image" "k6" {
  name          = docker_image.k6.name
  keep_remotely = true
  triggers = {
    dir_sha1 = sha1(join("", [for f in fileset("${path.cwd}/k6-docker-image", "**") : filesha1("${path.cwd}/k6-docker-image/${f}")]))
  }
}

resource "google_service_account" "k6" {
  account_id   = "ksix-sa"
  display_name = "Service Account"
}

resource "google_cloud_run_v2_job" "k6" {
  name     = "k6-test"
  location = var.region

  depends_on = [docker_image.k6, docker_registry_image.k6]

  template {
    parallelism = var.num-of-tasks
    task_count  = var.num-of-tasks
    template {
      service_account = google_service_account.k6.email
      timeout         = "86400s"
      max_retries     = 1

      containers {
        env {
          name  = "K6_OUT"
          value = "timescaledb=${local.database-url}"
        }

        image = "${local.docker-image}:latest"
        args  = ["/k6", "run", "script.js"]
        resources {
          limits = {
            cpu    = "8"
            memory = "4096Mi"
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      launch_stage,
    ]
  }
}
