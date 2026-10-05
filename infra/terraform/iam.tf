resource "google_service_account" "controller" {
  account_id   = "jenkins-controller"
  display_name = "Jenkins controller"
}

# Separate, least-privilege SA for agent VMs - never reuse the controller's SA
# here, or a compromised agent would inherit VM provisioning/deletion rights.
resource "google_service_account" "agent" {
  account_id   = "jenkins-agent"
  display_name = "Jenkins build agent"
}

resource "google_project_iam_custom_role" "gce_plugin" {
  role_id     = "jenkinsGcePlugin"
  title       = "Jenkins GCE Plugin"
  description = "Minimum permissions for the Jenkins GCE plugin to provision ephemeral agents"
  permissions = [
    "compute.instances.create",
    "compute.instances.delete",
    "compute.instances.get",
    "compute.instances.list",
    "compute.instances.setLabels",
    "compute.instances.setMetadata",
    "compute.instances.setTags",
    "compute.instances.setServiceAccount",
    "compute.instances.getGuestAttributes",
    "compute.disks.create",
    "compute.disks.use",
    "compute.disks.createSnapshot",
    "compute.snapshots.create",
    "compute.snapshots.delete",
    "compute.snapshots.get",
    "compute.images.get",
    "compute.images.list",
    "compute.images.useReadOnly",
    "compute.subnetworks.list",
    "compute.subnetworks.use",
    "compute.subnetworks.useExternalIp",
    "compute.networks.list",
    "compute.networks.use",
    "compute.networks.useExternalIp",
    "compute.instanceTemplates.get",
    "compute.instanceTemplates.list",
    "compute.instanceTemplates.useReadOnly",
    "compute.machineTypes.list",
    "compute.diskTypes.list",
    "compute.regions.list",
    "compute.zones.list",
    "compute.zones.get",
    "compute.zoneOperations.get",
    "compute.acceleratorTypes.list",
  ]
}

resource "google_project_iam_member" "controller_gce_plugin" {
  project = var.project_id
  role    = google_project_iam_custom_role.gce_plugin.id
  member  = "serviceAccount:${google_service_account.controller.email}"
}

# Required for the controller to attach the agent SA to the VMs it creates.
resource "google_service_account_iam_member" "controller_can_use_agent_sa" {
  service_account_id = google_service_account.agent.name
  role                = "roles/iam.serviceAccountUser"
  member              = "serviceAccount:${google_service_account.controller.email}"
}

# Agents push build artifacts/images - scope this down to a specific repository
# in production rather than project-wide writer access.
resource "google_project_iam_member" "agent_artifact_registry" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.agent.email}"
}
