# External HTTP load balancer in front of the controller VM - no TLS/cert
# here; map jenkins_lb_ip to your domain via Cloud DNS (and terminate TLS
# upstream of this, e.g. a CDN/another proxy, if needed).
#
# There's a single controller instance, so this doesn't distribute traffic
# across replicas - it mainly provides a stable public IP plus LB-level
# health awareness (stops routing to the instance if it's down).
resource "google_compute_global_address" "jenkins" {
  count = var.enable_jenkins_lb ? 1 : 0
  name  = "jenkins-lb-ip"
}

resource "google_compute_backend_service" "jenkins" {
  count                 = var.enable_jenkins_lb ? 1 : 0
  name                  = "jenkins-backend"
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 60
  health_checks         = [google_compute_health_check.controller.id]
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group = google_compute_instance_group.controller[0].id
  }
}

resource "google_compute_url_map" "jenkins" {
  count           = var.enable_jenkins_lb ? 1 : 0
  name            = "jenkins-url-map"
  default_service = google_compute_backend_service.jenkins[0].id
}

resource "google_compute_target_http_proxy" "jenkins" {
  count   = var.enable_jenkins_lb ? 1 : 0
  name    = "jenkins-http-proxy"
  url_map = google_compute_url_map.jenkins[0].id
}

resource "google_compute_global_forwarding_rule" "jenkins_http" {
  count                 = var.enable_jenkins_lb ? 1 : 0
  name                  = "jenkins-http"
  ip_address            = google_compute_global_address.jenkins[0].address
  port_range            = "80"
  target                = google_compute_target_http_proxy.jenkins[0].id
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

