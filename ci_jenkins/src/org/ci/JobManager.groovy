package org.ci

// Provisions (idempotently, via Job DSL) and triggers the companion integration-test
// job for a repo. The actual test pipeline lives in the consumer repo at
// .ci/integration-Jenkinsfile; if absent, a placeholder is generated from the
// library's default-integration-Jenkinsfile resource.
class JobManager implements Serializable {
    def script
    Map cfg

    JobManager(script, Map cfg) {
        this.script = script
        this.cfg = cfg
    }

    void ensureIntegrationJob() {
        if (!script.fileExists('.ci/integration-Jenkinsfile')) {
            String defaultPipeline = script.libraryResource('org/ci/default-integration-Jenkinsfile')
            script.writeFile file: '.ci/integration-Jenkinsfile', text: defaultPipeline
        }
        script.writeFile file: '.ci-seed/integration-job.groovy', text: jobDslScript()
        script.jobDsl targets: '.ci-seed/integration-job.groovy', removedJobAction: 'IGNORE'
    }

    void triggerIntegrationJob(String imageTag) {
        script.build(
            job: "${cfg.integrationJobFolder}/${cfg.integrationJobName}",
            parameters: [script.string(name: 'IMAGE_TAG', value: "${cfg.registry}/${imageTag}")],
            wait: true,
            propagate: true
        )
    }

    private String jobDslScript() {
        return """
pipelineJob('${cfg.integrationJobFolder}/${cfg.integrationJobName}') {
    description('Auto-generated integration test job for ${cfg.imageName}. Managed by ci-shared-library - do not edit manually.')
    parameters {
        stringParam('IMAGE_TAG', '', 'Docker image tag to test')
    }
    definition {
        cps {
            script(readFileFromWorkspace('.ci/integration-Jenkinsfile'))
            sandbox(true)
        }
    }
}
""".stripIndent()
    }
}
