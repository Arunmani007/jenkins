#!/usr/bin/env bash
# Optional: pre-pull the jenkins-build image into the machine image so one-shot
# agents don't pay a `docker pull` on every build. Requires the `google-cloud-cli`
# package (gcloud) and Artifact Registry read access from the Packer builder's
# service account.
set -euo pipefail

BUILD_IMAGE="${1:?usage: prepull-build-image.sh <image>}"

gcloud auth configure-docker "$(echo "$BUILD_IMAGE" | cut -d/ -f1)" --quiet
docker pull "$BUILD_IMAGE"
