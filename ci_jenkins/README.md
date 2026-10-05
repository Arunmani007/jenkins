# ci-shared-library

Jenkins shared library that gives every repository a standard, opinionated CI pipeline
triggered from a `Jenkinsfile` in that repo's `.ci/` folder.

```groovy
// repo/.ci/Jenkinsfile
@Library('ci-shared-library') _
ciPipeline()
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for diagrams and design rationale.

## What the pipeline does

1. **Ensure Integration Job** – idempotently creates/updates a companion Jenkins job
   (`integration-tests/<repo>-integration-tests`) via Job DSL, which runs the repo's
   `.ci/integration-Jenkinsfile` (or a placeholder if none exists).
2. **Build Image** – `docker build` using the repo's `Dockerfile`.
3. **Scan Image** – Trivy (CVE scan) + Dockle (container best practices); fails the
   build if CRITICAL/HIGH vulnerabilities are found (configurable).
4. **Push to Artifactory** – pushes the versioned image tag to the Artifactory Docker
   registry using bound credentials.
5. **Integration Tests** – triggers the companion job (step 1) with the new image tag
   and waits for the result, or runs an inline command if `integrationTestMode: inline`.
6. **Promote Image** – retags/pushes `:latest` only after integration tests pass, and
   only on `main`/`master`.

Plus, around those: checkout, config loading, Dockerfile linting (hadolint), optional
unit tests with JUnit reporting, Slack notification, and workspace/image cleanup —
these are the pieces that are easy to forget but matter for a production-grade CI
pipeline (see "Additional things covered" below).

## Repository layout

```
vars/                     Global pipeline step: ciPipeline()
src/org/ci/               Groovy helper classes (Config, DockerBuilder, SecurityScanner,
                           ArtifactoryPublisher, JobManager, Notifier)
resources/org/ci/         Non-groovy resources (default integration pipeline, sample
                           .trivyignore)
examples/consumer-repo/   Sample repo layout showing how to consume the library
docs/                     Architecture and design docs
```

## One-time Jenkins setup

1. **Install plugins**: Pipeline, Git, Docker Pipeline (or just the `docker` CLI on
   agents), Job DSL, Pipeline Utility Steps (`readYaml`), Credentials Binding, JUnit,
   Timestamper, Workspace Cleanup, Slack Notification (optional).
2. **Register the library**: *Manage Jenkins → System → Global Pipeline Libraries*
   - Name: `ci-shared-library`
   - Default version: a branch/tag, e.g. `main`
   - Retrieval method: Modern SCM → point at this repo
3. **Create the `integration-tests` folder** (or let the first Job DSL run create it —
   the `removedJobAction: IGNORE` setting requires the folder to already be
   addressable; create it once via *New Item → Folder* named `integration-tests`).
4. **Grant Job DSL script approval**: the seed job needs the *Job DSL* plugin's
   script-security approval the first time it runs (Job DSL scripts generated here are
   static/parameterized, not user-supplied, but review once in *Manage Jenkins → In-process
   Script Approval* if the sandbox blocks anything).
5. **Add credentials**: a Username/Password credential (`artifactory-creds` by default)
   with access to push to your Artifactory Docker repo.
6. **Create a Multibranch Pipeline / GitHub Organization folder** per repo (or per org),
   with **Script Path** set to `.ci/Jenkinsfile` (Jenkins does not look there by
   default — this is what makes "Jenkinsfile inside `.ci`" work).
7. **Agents**: need only the `docker` label, Docker Engine, and the Docker Pipeline
   plugin — `ciPipeline()` runs every stage inside the `buildImage` container (which
   carries `trivy`/`hadolint`/`dockle`/docker CLI), mounting the agent's docker socket
   (Docker-outside-of-Docker). See [infra/README.md](infra/README.md) to provision
   these agents on GCP as ephemeral, on-demand VMs.

## Consumer repo setup

```
repo/
  Dockerfile
  .ci/
    Jenkinsfile                # @Library('ci-shared-library') _ \n ciPipeline()
    ci-config.yaml             # optional overrides
    integration-Jenkinsfile    # optional custom integration test pipeline
```

See [examples/consumer-repo](examples/consumer-repo) for a complete example.

## Configuration reference (`.ci/ci-config.yaml` or `ciPipeline(...)` args)

| Key | Default | Description |
|---|---|---|
| `agentLabel` | `docker` | Node label to run the pipeline on |
| `buildImage` | `jenkins-build:latest` | Image every stage runs inside (see [infra/docker/jenkins-build](infra/docker/jenkins-build)) |
| `dockerfilePath` | `Dockerfile` | Path to the Dockerfile |
| `buildContext` | `.` | Docker build context |
| `imageName` | derived from job name | Image name (without registry/tag) |
| `registry` | `artifactory.example.com` | Artifactory Docker registry host |
| `artifactoryRepo` | `docker-local` | Artifactory repository name |
| `artifactoryCredentialsId` | `artifactory-creds` | Jenkins credentials ID (username/password) |
| `unitTestCommand` | `null` | If set, run before the build and publish JUnit results |
| `unitTestResultsPattern` | `**/test-results/*.xml` | JUnit XML glob |
| `vulnerabilitySeverity` | `CRITICAL,HIGH` | Severities passed to Trivy |
| `failOnVulnerabilities` | `true` | Fail the build if matching CVEs are found |
| `integrationTestMode` | `job` | `job` (companion Jenkins job) or `inline` |
| `integrationTestCommand` | `null` | Command to run when mode is `inline` |
| `integrationJobFolder` | `integration-tests` | Folder for generated integration jobs |
| `notifyChannel` | `null` | Slack channel; notifications skipped if unset |
| `pushEnabled` | `true` on `main`/`master`, else `false` | Whether to push/promote |

## Additional things covered beyond the original 4 steps

These are easy to miss but are included because they matter for a real CI pipeline:

- **Dockerfile linting** (hadolint) before spending time building.
- **Unit tests** as an explicit, optional stage with JUnit reporting, run before the
  (slower) image build so failures are caught early.
- **Deterministic, traceable image tags**: `<branch>-<build-number>-<short-sha>`,
  rather than relying solely on `:latest`.
- **Fail-fast vulnerability gate** with a configurable severity threshold, and raw
  Trivy/Dockle reports archived as build artifacts for audit.
- **Separate "candidate" vs "promoted" tags**: `:latest` is only pushed after
  integration tests pass, so a broken image is never the one a `latest` puller gets.
- **Push is skipped on branches/PRs** that don't match `pushEnabled` (default:
  main/master only) — so every PR still gets a build + scan, but registries aren't
  polluted with throwaway images.
- **Secrets never touch disk/logs**: Artifactory credentials are bound with
  `withCredentials` and passed to `docker login` via stdin.
- **Idempotent integration job provisioning**: the companion job is (re)created via
  Job DSL on every run so it never drifts from what the repo expects, and the repo
  owns its own integration test logic (`.ci/integration-Jenkinsfile`).
- **Cleanup**: workspace and locally built images are removed in a `finally` block
  regardless of outcome, so agents don't fill up with stale images.
- **Notifications**: a single `post`-style notifier reports success/failure to Slack.

## Suggested future enhancements

- SBOM generation (e.g. `syft`) archived alongside the image, and optionally image
  signing (`cosign`) before promotion.
- SonarQube/static analysis stage alongside unit tests.
- Parallelize unit tests and Dockerfile lint.
- Multi-arch builds (`docker buildx`).
- Promote by retagging the already-scanned digest instead of rebuilding, to guarantee
  "what was scanned is what ships".
