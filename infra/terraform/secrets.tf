# Bootstrap admin credentials and the GitHub token used for repo discovery are
# generated/stored here rather than hardcoded in casc/jenkins.yaml.tftpl, so no
# plaintext secret ever lands in the JCasC file or this repo.

resource "random_password" "jenkins_admin" {
  length  = 24
  special = true
}

resource "google_secret_manager_secret" "jenkins_admin_password" {
  secret_id = "jenkins-admin-password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "jenkins_admin_password" {
  secret      = google_secret_manager_secret.jenkins_admin_password.id
  secret_data = random_password.jenkins_admin.result
}

resource "google_secret_manager_secret_iam_member" "controller_reads_admin_password" {
  secret_id = google_secret_manager_secret.jenkins_admin_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.controller.email}"
}

# GitHub PAT (repo scope) for the auto-created Organization Folder to discover
# repos containing .ci/Jenkinsfile. Pass via TF_VAR_github_token so it never
# touches a .tfvars file or shell history.
variable "github_token" {
  type        = string
  description = "GitHub personal access token (repo scope) for organization folder scanning. Leave empty to skip creating the credential/job."
  sensitive   = true
  default     = ""
}

resource "google_secret_manager_secret" "github_token" {
  secret_id = "jenkins-github-token"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "github_token" {
  count       = var.github_token != "" ? 1 : 0
  secret      = google_secret_manager_secret.github_token.id
  secret_data = var.github_token
}

resource "google_secret_manager_secret_iam_member" "controller_reads_github_token" {
  secret_id = google_secret_manager_secret.github_token.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.controller.email}"
}

output "jenkins_admin_password_secret_id" {
  value       = google_secret_manager_secret.jenkins_admin_password.secret_id
  description = "Fetch the generated admin password with: gcloud secrets versions access latest --secret=<this value>"
}
