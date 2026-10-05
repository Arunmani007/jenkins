package org.ci

// Resolves pipeline configuration from (in increasing precedence):
// defaults -> .ci/ci-config.yaml in the consumer repo -> args passed to ciPipeline()
class Config implements Serializable {
    def script
    Map userConfig

    Config(script, Map userConfig = [:]) {
        this.script = script
        this.userConfig = userConfig
    }

    Map load() {
        Map defaults = [
            agentLabel              : 'docker',
            // Image every pipeline stage runs inside (docker CLI, git, trivy, hadolint,
            // dockle). The agent VM only needs Docker Engine - see infra/packer.
            buildImage               : 'us-docker.pkg.dev/my-project/ci/jenkins-build:latest',
            dockerfilePath           : 'Dockerfile',
            buildContext             : '.',
            imageName                : defaultImageName(),
            registry                 : 'artifactory.example.com',
            artifactoryRepo          : 'docker-local',
            artifactoryCredentialsId : 'artifactory-creds',
            unitTestCommand          : null,
            unitTestResultsPattern   : '**/test-results/*.xml',
            vulnerabilitySeverity    : 'CRITICAL,HIGH',
            failOnVulnerabilities    : true,
            pushEnabled              : (script.env.BRANCH_NAME == 'main' || script.env.BRANCH_NAME == 'master'),
            integrationTestMode      : 'job', // 'job' (companion Jenkins job) or 'inline' (run a command)
            integrationTestCommand   : null,
            integrationJobFolder    : 'integration-tests',
            notifyChannel            : null,
            pipelineTimeoutMinutes   : 60,
        ]

        Map fileConfig = [:]
        if (script.fileExists('.ci/ci-config.yaml')) {
            fileConfig = script.readYaml(file: '.ci/ci-config.yaml') ?: [:]
        }

        Map merged = defaults + fileConfig + userConfig
        merged.integrationJobName = "${merged.imageName}-integration-tests"
        return merged
    }

    private String defaultImageName() {
        String jobName = script.env.JOB_NAME ?: 'app'
        // Multibranch job names look like "folder/repo/branch" - keep just the repo segment.
        String repo = jobName.tokenize('/')[0]
        return repo.toLowerCase().replaceAll('[^a-z0-9-_]', '-')
    }
}
