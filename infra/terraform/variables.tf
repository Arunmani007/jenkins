variable "project_id" {
  type        = string
  description = "GCP project ID hosting the Jenkins controller and ephemeral agents"
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "network_name" {
  type    = string
  default = "jenkins-vpc"
}

variable "subnet_cidr" {
  type    = string
  default = "10.10.0.0/24"
}

variable "controller_machine_type" {
  type    = string
  default = "e2-standard-2"
}

variable "controller_image" {
  type        = string
  default     = "jenkins/jenkins:lts-jdk17"
  description = "Jenkins controller container image"
}

variable "agent_machine_type" {
  type    = string
  default = "e2-medium"
}

variable "agent_image_family" {
  type        = string
  default     = "jenkins-gce-agent"
  description = "Image family built by infra/packer/gce-agent-image.pkr.hcl"
}

variable "instance_cap" {
  type        = number
  default     = 10
  description = "Max concurrent ephemeral agent VMs"
}

variable "admin_access_cidrs" {
  type        = list(string)
  default     = []
  description = "CIDR ranges allowed direct access to the Jenkins UI (port 8080). Leave empty to require an IAP tunnel instead of exposing it on the VPC."
}

variable "admin_username" {
  type        = string
  default     = "admin"
  description = "Bootstrap Jenkins admin user. Password is generated and stored in Secret Manager - see output jenkins_admin_password_secret_id."
}

variable "shared_library_repo_url" {
  type        = string
  description = "Git URL of the ci-shared-library repo, registered as a Global Pipeline Library via JCasC"
}

variable "shared_library_default_version" {
  type    = string
  default = "main"
}

variable "github_org" {
  type        = string
  default     = ""
  description = "GitHub org/user to auto-scan for repos with a .ci/Jenkinsfile (Organization Folder). Leave empty to skip."
}

variable "github_credentials_id" {
  type    = string
  default = "github-token"
}

