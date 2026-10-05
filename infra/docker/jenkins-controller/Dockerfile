# Optional: bake required plugins into the controller image so Terraform's
# startup-script deployment is fully hands-off (no manual plugin install step).
# Build and push this, then set controller_image to the pushed reference.
FROM jenkins/jenkins:lts-jdk17

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
