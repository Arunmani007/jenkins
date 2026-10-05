resource "google_project_service" "required" {
  for_each = toset([
    "compute.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "artifactregistry.googleapis.com",
    "iap.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
