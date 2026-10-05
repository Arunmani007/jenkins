output "controller_internal_ip" {
  value       = google_compute_address.controller_internal.address
  description = "Reach the Jenkins UI via an IAP tunnel to this address on port 8080"
}

output "controller_service_account_email" {
  value = google_service_account.controller.email
}

output "agent_service_account_email" {
  value = google_service_account.agent.email
}

output "network_name" {
  value = google_compute_network.jenkins.name
}

output "subnetwork_name" {
  value = google_compute_subnetwork.jenkins.name
}
