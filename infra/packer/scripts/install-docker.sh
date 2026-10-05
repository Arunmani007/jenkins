#!/usr/bin/env bash
# Installs Docker Engine. The agent VM only runs containers - all build tooling
# (trivy, hadolint, dockle, docker CLI) lives in the jenkins-build image instead.
set -euo pipefail

apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io

systemctl enable docker
systemctl restart docker
docker version
