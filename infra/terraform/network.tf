resource "google_compute_network" "jenkins" {
  name                    = var.network_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "jenkins" {
  name          = "${var.network_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.jenkins.id
}

# Agents have no external IP (see casc/jenkins.yaml.tftpl); Cloud NAT lets them
# still reach the internet to pull images and update vulnerability DBs.
resource "google_compute_router" "jenkins" {
  name    = "${var.network_name}-router"
  network = google_compute_network.jenkins.id
  region  = var.region
}

resource "google_compute_router_nat" "jenkins" {
  name                               = "${var.network_name}-nat"
  router                             = google_compute_router.jenkins.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_firewall" "controller_to_agent_ssh" {
  name    = "${var.network_name}-controller-to-agent-ssh"
  network = google_compute_network.jenkins.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_tags = ["jenkins-controller"]
  target_tags = ["jenkins-agent"]
}

# Opt-in only: direct access to the Jenkins UI from specific CIDRs.
resource "google_compute_firewall" "jenkins_ui_admin" {
  count   = length(var.admin_access_cidrs) > 0 ? 1 : 0
  name    = "${var.network_name}-jenkins-ui-admin"
  network = google_compute_network.jenkins.id

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  target_tags   = ["jenkins-controller"]
  source_ranges = var.admin_access_cidrs
}

# Always-on, safe default: reach the controller UI and SSH via Identity-Aware
# Proxy tunnels (`gcloud compute start-iap-tunnel`) instead of public exposure.
resource "google_compute_firewall" "iap_access" {
  name    = "${var.network_name}-iap-access"
  network = google_compute_network.jenkins.id

  allow {
    protocol = "tcp"
    ports    = ["22", "8080"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["jenkins-controller", "jenkins-agent"]
}

# Google Front End (health checks + proxied traffic) ranges for the external
# load balancer - required even though the controller has no external IP of
# its own, since the LB reaches backends over the VPC.
resource "google_compute_firewall" "lb_to_controller" {
  count   = var.enable_jenkins_lb ? 1 : 0
  name    = "${var.network_name}-lb-to-controller"
  network = google_compute_network.jenkins.id

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["jenkins-controller"]
}
