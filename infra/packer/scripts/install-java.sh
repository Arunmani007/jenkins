#!/usr/bin/env bash
# Installs Java (required by the Jenkins GCE plugin's SSH launcher) and sshd.
set -euo pipefail

apt-get update
apt-get install -y --no-install-recommends \
    openjdk-21-jre-headless \
    openssh-server \
    ca-certificates \
    curl

systemctl enable ssh
systemctl restart ssh

java -version
