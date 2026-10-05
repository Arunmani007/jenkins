packer {
  required_plugins {
    googlecompute = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/googlecompute"
    }
  }
}

variable "project_id" {
  type        = string
  description = "GCP project to build the image in"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "image_family" {
  type        = string
  default     = "jenkins-gce-agent"
  description = "Image family referenced by the Terraform/JCasC agent configuration"
}

variable "machine_type" {
  type    = string
  default = "e2-medium"
}

variable "build_image" {
  type        = string
  default     = ""
  description = "Optional jenkins-build image reference to pre-pull (e.g. us-docker.pkg.dev/PROJECT/ci/jenkins-build:latest). Leave empty to skip."
}

source "googlecompute" "agent" {
  project_id              = var.project_id
  zone                     = var.zone
  source_image_family      = "debian-12"
  source_image_project_id  = ["debian-cloud"]
  image_name               = "${var.image_family}-{{timestamp}}"
  image_family             = var.image_family
  machine_type             = var.machine_type
  disk_size                = 30
  ssh_username             = "packer"
}

build {
  name    = "jenkins-gce-agent"
  sources = ["source.googlecompute.agent"]

  provisioner "shell" {
    script          = "scripts/install-java.sh"
    execute_command = "sudo -E bash '{{ .Path }}'"
  }

  provisioner "shell" {
    script          = "scripts/install-docker.sh"
    execute_command = "sudo -E bash '{{ .Path }}'"
  }

  provisioner "shell" {
    script          = "scripts/prepull-build-image.sh"
    execute_command = "sudo -E bash '{{ .Path }}' '${var.build_image}'"
    only            = var.build_image != "" ? ["googlecompute.agent"] : []
  }
}
