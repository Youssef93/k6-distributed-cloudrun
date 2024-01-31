resource "google_service_account" "vm" {
  account_id   = "k6-timescale-vm"
  display_name = "Custom SA for VM Instance"
}

resource "google_compute_instance" "k6" {
  name         = "timescale-db-instance"
  machine_type = "n2-standard-2"
  zone         = "${var.region}-a"

  tags = ["vm-pg-instance"]

  boot_disk {
    initialize_params {
      image = "ubuntu-2004-lts"
      size  = var.database-disk-size
    }
  }

  deletion_protection = false

  // Local SSD disk
  scratch_disk {
    interface = "NVME"
  }

  # network & vpc in which VM instance is deployed
  # might need to allow some firewall rules
  network_interface {
    network = var.vpc-name

    access_config {
    }
  }

  metadata_startup_script = templatefile("${path.cwd}/vm-startup-script.sh.tftpl", {
    DATABASE_PASSWORD = var.DATABASE_PASSWORD
    DATABASE_NAME     = var.DATABASE_NAME
  })

  metadata = {
    serial-port-enable = 1
  }

  service_account {
    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    email  = google_service_account.vm.email
    scopes = ["cloud-platform"]
  }
}

resource "google_compute_firewall" "allow-postgres-traffic" {
  count     = var.add-firewall-rule ? 1 : 0
  name      = "allow-all-trafic-to-postgres"
  network   = var.vpc-name
  project   = var.project
  priority  = 1000
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["vm-pg-instance"]
}
