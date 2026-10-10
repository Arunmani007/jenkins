resource "google_compute_address" "controller_internal" {
  name         = "jenkins-controller-ip"
  region       = var.region
  subnetwork   = google_compute_subnetwork.jenkins.id
  address_type = "INTERNAL"
}

locals {
  # Prefer the public domain (once the LB + Cloud DNS mapping exist) over the
  # internal IP for Jenkins' own notion of its URL.
  jenkins_url = var.enable_jenkins_lb && var.jenkins_domain_name != "" ? "http://${var.jenkins_domain_name}/" : "http://${google_compute_address.controller_internal.address}:8080/"

  casc_yaml = templatefile("${path.module}/casc/jenkins.yaml.tftpl", {
    project_id                     = var.project_id
    region                          = var.region
    zone                            = var.zone
    network                         = google_compute_network.jenkins.name
    subnetwork                      = google_compute_subnetwork.jenkins.name
    agent_image_family              = var.agent_image_family
    agent_machine_type              = var.agent_machine_type
    agent_service_account_email     = google_service_account.agent.email
    instance_cap                    = var.instance_cap
    cloud_name                      = "gcp-ephemeral-agents"
    jenkins_url                     = local.jenkins_url
    admin_username                  = var.admin_username
    admin_usernames                 = distinct(concat([var.admin_username], var.additional_admin_usernames))
    shared_library_repo_url         = var.shared_library_repo_url
    shared_library_default_version  = var.shared_library_default_version
    github_org                      = var.github_org
    github_credentials_id           = var.github_credentials_id
  })

  controller_startup_script = <<-EOT
    #!/bin/bash
    set -euo pipefail
    apt-get update && apt-get install -y docker.io apt-transport-https ca-certificates gnupg curl

    if ! command -v gcloud >/dev/null 2>&1; then
      echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
        > /etc/apt/sources.list.d/google-cloud-sdk.list
      curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
      apt-get update && apt-get install -y google-cloud-cli
    fi

    systemctl enable --now docker

    device=/dev/disk/by-id/google-jenkins-home
    mount_point=/var/jenkins_home
    mkdir -p "$mount_point"
    blkid "$device" || mkfs.ext4 -F "$device"
    mountpoint -q "$mount_point" || mount "$device" "$mount_point"
    grep -q "$device" /etc/fstab || echo "$device $mount_point ext4 defaults 0 2" >> /etc/fstab

    cat <<'CASC' > "$mount_point/casc.yaml"
    ${local.casc_yaml}
    CASC

    admin_password=$(gcloud secrets versions access latest --secret=${google_secret_manager_secret.jenkins_admin_password.secret_id} --project=${var.project_id})
    github_token=$(gcloud secrets versions access latest --secret=${google_secret_manager_secret.github_token.secret_id} --project=${var.project_id} 2>/dev/null || echo "")

    docker run -d --name jenkins --restart unless-stopped \
      -p 8080:8080 -p 50000:50000 \
      -v "$mount_point:/var/jenkins_home" \
      -e CASC_JENKINS_CONFIG=/var/jenkins_home/casc.yaml \
      -e ADMIN_PASSWORD="$admin_password" \
      -e GITHUB_TOKEN="$github_token" \
      ${var.controller_image}
  EOT
}

# Jenkins' controller is a stateful, single-writer process (JENKINS_HOME,
# in-memory build queue/executors) - it runs as a single VM, not a cluster.
# This health check is only used for the optional load balancer's backend
# health awareness (see loadbalancer.tf), not auto-healing/recreation.
resource "google_compute_health_check" "controller" {
  name                = "jenkins-controller-hc"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = 8080
    request_path = "/login"
  }
}

resource "google_compute_instance" "controller" {
  name         = "jenkins-controller"
  machine_type = var.controller_machine_type
  zone         = var.zone
  tags         = ["jenkins-controller"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 50
      type  = "pd-ssd"
    }
  }

  # Separate, persistent data disk for JENKINS_HOME so the controller can be
  # recreated without losing build history/config.
  attached_disk {
    source      = google_compute_disk.jenkins_home.self_link
    device_name = "jenkins-home"
  }

  network_interface {
    subnetwork = google_compute_subnetwork.jenkins.id
    network_ip = google_compute_address.controller_internal.address
    # No access_config block -> no external IP. Use an IAP tunnel to reach it.
  }

  service_account {
    email  = google_service_account.controller.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    startup-script = local.controller_startup_script
  }

  allow_stopping_for_update = true
}

# Unmanaged instance group wrapping the single VM, solely so the optional
# load balancer's backend service has something to point at.
resource "google_compute_instance_group" "controller" {
  count     = var.enable_jenkins_lb ? 1 : 0
  name      = "jenkins-controller-ig"
  zone      = var.zone
  instances = [google_compute_instance.controller.self_link]

  named_port {
    name = "http"
    port = 8080
  }
}

resource "google_compute_disk" "jenkins_home" {
  name = "jenkins-home"
  zone = var.zone
  size = 100
  type = "pd-ssd"

  lifecycle {
    prevent_destroy = true
  }
}
