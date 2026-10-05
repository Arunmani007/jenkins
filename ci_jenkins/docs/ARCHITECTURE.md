# Architecture

## System context

```mermaid
flowchart LR
    Dev[Developer] -->|git push .ci/Jenkinsfile| Repo[(App Repo)]
    Repo -->|webhook| Jenkins[Jenkins Controller]
    Jenkins -->|Script Path: .ci/Jenkinsfile| MB[Multibranch Pipeline Job]
    MB -->|"@Library('ci-shared-library')"| Lib[ci-shared-library]
    Lib --> Agent[Build Agent: docker, trivy, hadolint, dockle]
    Agent -->|push image| Artifactory[(Artifactory Docker Registry)]
    Lib -->|Job DSL: create/update| IntJob[Integration Test Job]
    Lib -->|trigger + wait| IntJob
    IntJob -->|pull image| Artifactory

    Lib -->|notify| Slack[Slack]
```

## Pipeline sequence

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant Repo as App Repo (.ci/Jenkinsfile)
    participant J as Jenkins (ciPipeline)
    participant A as Build Agent
    participant Trivy as Trivy/Dockle
    participant Art as Artifactory
    participant IT as Integration Job

    Dev->>Repo: push commit
    Repo->>J: webhook triggers multibranch scan
    J->>J: Checkout + Load Configuration (.ci/ci-config.yaml)
    J->>A: Validate Dockerfile (hadolint)
    J->>A: Unit Tests (optional)
    J->>J: Ensure Integration Job (Job DSL, idempotent)
    J->>A: docker build -> image:tag
    A->>Trivy: scan image
    Trivy-->>J: report + pass/fail vs severity threshold
    alt scan failed
        J-->>Dev: build FAILURE (reports archived)
    else scan passed
        J->>Art: docker push image:tag
        J->>IT: trigger(IMAGE_TAG) and wait
        IT->>Art: docker pull image:tag
        IT-->>J: pass/fail
        alt integration tests passed and branch is main
            J->>Art: tag + push :latest
        end
        J-->>Dev: build result + Slack notification
    end
    J->>A: cleanup (docker rmi, workspace)
```

## Library component diagram

```mermaid
classDiagram
    class ciPipeline {
        +call(Map userConfig)
    }
    class Config {
        +load() Map
    }
    class DockerBuilder {
        +lint()
        +build(imageTag)
    }
    class SecurityScanner {
        +scan(imageTag)
    }
    class ArtifactoryPublisher {
        +push(imageTag)
        +promote(imageTag)
    }
    class JobManager {
        +ensureIntegrationJob()
        +triggerIntegrationJob(imageTag)
    }
    class Notifier {
        +notify(result)
    }

    ciPipeline --> Config
    ciPipeline --> DockerBuilder
    ciPipeline --> SecurityScanner
    ciPipeline --> ArtifactoryPublisher
    ciPipeline --> JobManager
    ciPipeline --> Notifier
```

## Key design decisions

- **Scripted pipeline inside `vars/ciPipeline.groovy`** rather than declarative, because
  stage list depends on configuration only known after checkout (e.g. whether
  `.ci/ci-config.yaml` enables unit tests or inline integration tests). Declarative's
  static stage graph doesn't support this without heavier workarounds.
- **Integration tests run in a separate, generated Jenkins job** instead of inline
  steps. This lets integration tests use their own environment lifecycle
  (docker-compose, ephemeral namespace, etc.), be re-run independently of a full CI
  build, and keeps the CI job focused on build/scan/publish. The companion job's
  *pipeline definition* still lives in the consumer repo (`.ci/integration-Jenkinsfile`)
  so teams own their own test logic; the shared library only owns job provisioning and
  orchestration (`integrationTestMode: inline` is available for teams that prefer a
  single-job model instead).
- **Promotion is separate from publish**: the versioned tag is pushed immediately
  (so it exists for the integration job to pull), but the floating `:latest` tag is
  only created after integration tests succeed, preventing a broken image from ever
  being `:latest`.
- **Registry push is gated by branch** (`pushEnabled`) so every branch/PR still gets a
  full build + scan for fast feedback, without polluting the registry with
  non-release images.
- **Config precedence** `defaults -> .ci/ci-config.yaml -> ciPipeline(...) args` lets
  platform defaults apply everywhere, repos self-serve common overrides via a
  versioned file, and still allows one-off overrides directly in the Jenkinsfile.

## GCP infrastructure (`infra/`)

The controller and agents are provisioned as code - see [infra/README.md](../infra/README.md)
for deployment steps.

```mermaid
flowchart TB
    subgraph VPC["GCP VPC (no external IPs)"]
        Controller["Jenkins Controller<br/>GCE VM, persistent disk<br/>JCasC-configured"]
        subgraph Agent["Agent VM (one-shot, created per build)"]
            Docker["Docker Engine"]
            BuildC["jenkins-build container<br/>docker CLI, git, trivy, hadolint, dockle"]
            Docker -.->|host socket mounted in| BuildC
        end
        Controller -->|"SSH (GCE plugin)"| Agent
        NAT["Cloud NAT"]
        Agent -->|egress| NAT
    end
    IAP["Identity-Aware Proxy tunnel"] -->|admin access, 8080/22| Controller
    BuildC -->|push| Artifactory[(Artifactory)]
    GCEPlugin["GCE Plugin"] -.->|create/delete, oneShot| Agent
    Controller --- GCEPlugin
```

Why the agent VM stays minimal (Java, SSH, Docker Engine only) while all build
tooling lives in the `jenkins-build` image: the Jenkins GCE plugin launches
agents over **SSH** and starts a plain Java remoting process — it has no native
"run the agent as a container" mode. Keeping tooling in a container instead of
baking it onto the VM means `ciPipeline()`'s `buildImage` can be versioned and
upgraded independently of the (rarely-changing) machine image, and keeps the
Packer image small and fast to boot for one-shot agents.

