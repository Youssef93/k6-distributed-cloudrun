locals {
  grafana-docker-image = "${var.region}-docker.pkg.dev/${var.project}/${google_artifact_registry_repository.grafana.name}/grafana"
}

# Override template file with actual database source information
resource "local_file" "datasource" {
  content = templatefile("${path.cwd}/grafana-docker-image/datasources/datasource.yml.tftpl", {
    DATABASE_HOST     = google_compute_instance.k6.network_interface[0].access_config[0].nat_ip
    DATABASE_PASSWORD = var.DATABASE_PASSWORD
    DATABASE_NAME     = var.DATABASE_NAME
    DATABASE_USER     = var.DATABASE_USER
  })
  filename = "${path.cwd}/grafana-docker-image/datasources/datasource.yml"
}

resource "google_artifact_registry_repository" "grafana" {
  location      = var.region
  repository_id = "grafana"
  description   = "Grafana docker image artifact registry"
  format        = "DOCKER"
}

resource "docker_image" "grafana" {
  name       = local.grafana-docker-image
  depends_on = [local_file.datasource]
  build {
    context  = "${path.cwd}/grafana-docker-image"
    platform = var.docker-platform
  }
}

resource "docker_registry_image" "grafana" {
  name          = docker_image.grafana.name
  keep_remotely = true
}

resource "google_service_account" "grafana" {
  account_id   = "grafana"
  display_name = "Service Account"
}

# Cloud run instance
resource "google_cloud_run_service" "grafana" {
  name                       = "grafana"
  autogenerate_revision_name = true
  location                   = var.region

  depends_on = [docker_image.grafana]

  template {
    spec {

      containers {
        image = "${local.grafana-docker-image}:latest"

        ports {
          container_port = var.grafana-port
        }

        resources {
          limits = {
            cpu    = "1000m"
            memory = "512Mi"
          }
        }

        env {
          name  = "GF_AUTH_ANONYMOUS_ORG_ROLE"
          value = "Admin"
        }
        env {
          name  = "GF_AUTH_ANONYMOUS_ENABLED"
          value = "true"
        }
        env {
          name  = "GF_AUTH_BASIC_ENABLED"
          value = "false"
        }

        startup_probe {
          http_get {
            port = var.grafana-port
          }

          # Grafana takes time to initialize
          initial_delay_seconds = 30
          failure_threshold     = 20
          timeout_seconds       = 20
          period_seconds        = 30
        }
      }

      service_account_name = google_service_account.grafana.email
    }
    metadata {
      annotations = {
        "autoscaling.knative.dev/minScale" = 1,
        # max should be one only as grafana is using internal sqlite
        # if we need more insatnces then we need to provide an external db to grafana
        "autoscaling.knative.dev/maxScale" = 1
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  lifecycle {
    ignore_changes = [
      template[0].metadata[0].annotations["client.knative.dev/user-image"],
      template[0].metadata[0].annotations["run.googleapis.com/client-name"],
      template[0].metadata[0].annotations["run.googleapis.com/client-version"],
      template[0].metadata[0].labels["run.googleapis.com/startupProbeType"],
      metadata[0].annotations["client.knative.dev/user-image"],
      metadata[0].annotations["run.googleapis.com/client-name"],
      metadata[0].annotations["run.googleapis.com/client-version"],
      template[0].metadata[0].annotations["run.googleapis.com/startup-cpu-boost"],
      template[0].metadata[0].labels["client.knative.dev/nonce"],
    ]

    replace_triggered_by = [docker_registry_image.grafana.sha256_digest]
  }
}

# allow unauthenticated access to service
resource "google_cloud_run_service_iam_policy" "noauth-grafana" {
  location = google_cloud_run_service.grafana.location
  project  = google_cloud_run_service.grafana.project
  service  = google_cloud_run_service.grafana.name

  policy_data = jsonencode(
    {
      bindings = [
        {
          members = [
            "allUsers",
          ]
          role = "roles/run.invoker"
        },
      ]
    }
  )
}
