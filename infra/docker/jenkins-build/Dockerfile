# Pipeline build image: carries every tool the CI stages need (docker CLI, git,
# trivy, hadolint, dockle). The GCE agent VM only needs Docker Engine - this image
# is what `docker.image(cfg.buildImage).inside(...)` actually executes stages in.
FROM docker:27-cli

ARG TRIVY_VERSION=0.54.1
ARG HADOLINT_VERSION=2.12.0
ARG DOCKLE_VERSION=0.4.14

RUN apk add --no-cache \
        bash \
        git \
        curl \
        jq \
        ca-certificates \
        openjdk17-jre-headless

RUN curl -fsSL "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" \
        -o /tmp/trivy.tgz \
    && tar -xzf /tmp/trivy.tgz -C /usr/local/bin trivy \
    && rm /tmp/trivy.tgz

RUN curl -fsSL "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-Linux-x86_64" \
        -o /usr/local/bin/hadolint \
    && chmod +x /usr/local/bin/hadolint

RUN curl -fsSL "https://github.com/goodwithtech/dockle/releases/download/v${DOCKLE_VERSION}/dockle_${DOCKLE_VERSION}_Linux-64bit.tar.gz" \
        -o /tmp/dockle.tgz \
    && tar -xzf /tmp/dockle.tgz -C /usr/local/bin dockle \
    && rm /tmp/dockle.tgz

# openjdk17-jre-headless is only needed if your unitTestCommand runs a JVM build tool
# (Maven/Gradle); remove it (and add your own runtime) if the repos you build don't need it.

WORKDIR /workspace
