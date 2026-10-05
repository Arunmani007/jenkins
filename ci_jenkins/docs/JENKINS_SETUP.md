# Jenkins Setup Guide

One-time Jenkins controller/agent setup required to use `ci-shared-library`, plus the
per-repo steps to onboard a consumer repository.

## 1. Install plugins

*Manage Jenkins → Plugins*, install:

- Pipeline, Pipeline: Groovy
- Git
- Job DSL
- Pipeline Utility Steps (provides `readYaml`)
- Credentials Binding
- JUnit
- Timestamper
- Workspace Cleanup
- Slack Notification (only if you set `notifyChannel`)

## 2. Register the shared library globally

*Manage Jenkins → System → Global Pipeline Libraries → Add*

- **Name**: `ci-shared-library` (must match `@Library('ci-shared-library')` in consumer Jenkinsfiles)
- **Default version**: `main`
- **Retrieval method**: Modern SCM → Git
- **Project repository**: `https://github.com/Arunmani007/jenkins.git`
- Leave "Load implicitly" unchecked (consumers opt in explicitly via `@Library`)

## 3. Create the integration jobs folder

*New Item → Folder* named `integration-tests` (must match the `integrationJobFolder`
default). The Job DSL step in [src/org/ci/JobManager.groovy](../src/org/ci/JobManager.groovy)
creates jobs *inside* this folder but won't create the folder itself.

## 4. Add credentials

*Manage Jenkins → Credentials → (global)*:

- Username/password credential with ID `artifactory-creds` (must have push rights to
  your Artifactory Docker repo)
- Git credentials/SSH key if your repos aren't public

## 5. Prepare build agents

Any agent labeled `docker` (the default `agentLabel`) needs the following installed
and on `PATH`:

```
docker, trivy, hadolint, dockle
```

If you use different labels, set `agentLabel` in `.ci/ci-config.yaml` per repo.

## 6. First-run script approval

Job DSL and credentials/`sh` steps run inside the pipeline's CPS sandbox. The first
time the pipeline runs, check *Manage Jenkins → In-process Script Approval* and
approve anything flagged.

## 7. Create the per-repo Jenkins job

For each consumer repo, either:

- **Multibranch Pipeline**: *New Item → Multibranch Pipeline* → point Branch Source at
  the repo → under **Build Configuration**, set **Script Path** to `.ci/Jenkinsfile`
  (critical, easy-to-miss step — Jenkins looks for `Jenkinsfile` at the repo root by
  default)
- or a **GitHub Organization Folder** for auto-discovery across many repos, with the
  same Script Path override applied via its job configuration

## 8. Add the files to the consumer repo

```
repo/.ci/Jenkinsfile        → @Library('ci-shared-library') _ \n ciPipeline()
repo/.ci/ci-config.yaml     → optional overrides (imageName, registry, etc.)
repo/Dockerfile
```

Copy from [examples/consumer-repo](../examples/consumer-repo) as a starting point.

## 9. Configure the webhook

In the repo (or org), add a webhook to your Jenkins URL (`/github-webhook/` for
GitHub) so pushes trigger a multibranch scan automatically — otherwise you're relying
on periodic polling.

## 10. Verify end-to-end

Push a commit touching `.ci/Jenkinsfile` and confirm:

1. The job appears/scans
2. The pipeline runs through all stages
3. The `integration-tests/<repo>-integration-tests` job gets created
4. The image lands in Artifactory
