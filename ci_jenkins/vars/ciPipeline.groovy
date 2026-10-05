import org.ci.Config
import org.ci.DockerBuilder
import org.ci.SecurityScanner
import org.ci.ArtifactoryPublisher
import org.ci.JobManager
import org.ci.Notifier

// Entry point called from a repo's .ci/Jenkinsfile, e.g.:
//   @Library('ci-shared-library') _
//   ciPipeline()
def call(Map userConfig = [:]) {
    node(userConfig.agentLabel ?: 'docker') {
        Map cfg = null
        String imageTag = null
        try {
            timestamps {
                stage('Checkout') {
                    checkout scm
                }

                stage('Load Configuration') {
                    cfg = new Config(this, userConfig).load()
                    String shortSha = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    imageTag = "${cfg.imageName}:${env.BRANCH_NAME}-${env.BUILD_NUMBER}-${shortSha}"
                }

                // Mount the agent VM's docker socket so `docker build/push` run from
                // inside the build container but are executed by the host's daemon
                // (Docker-outside-of-Docker - no privileged nested Docker needed).
                String dockerGid = sh(script: "stat -c '%g' /var/run/docker.sock", returnStdout: true).trim()
                String containerArgs = "-v /var/run/docker.sock:/var/run/docker.sock --group-add ${dockerGid}"

                docker.image(cfg.buildImage).inside(containerArgs) {
                    stage('Validate Dockerfile') {
                        new DockerBuilder(this, cfg).lint()
                    }

                    if (cfg.unitTestCommand) {
                        stage('Unit Tests') {
                            sh cfg.unitTestCommand
                            junit allowEmptyResults: true, testResults: cfg.unitTestResultsPattern
                        }
                    }

                    // 1. Create/ensure the companion integration test job exists.
                    if (cfg.integrationTestMode == 'job') {
                        stage('Ensure Integration Job') {
                            new JobManager(this, cfg).ensureIntegrationJob()
                        }
                    }

                    // 2. Build the image from the Dockerfile in the repo.
                    stage('Build Image') {
                        new DockerBuilder(this, cfg).build(imageTag)
                    }

                    // 3. Scan the image for vulnerabilities and quality issues.
                    stage('Scan Image') {
                        new SecurityScanner(this, cfg).scan(imageTag)
                    }

                    if (cfg.pushEnabled) {
                        // 4. Push the built, scanned image to Artifactory.
                        stage('Push to Artifactory') {
                            new ArtifactoryPublisher(this, cfg).push(imageTag)
                        }

                        stage('Integration Tests') {
                            if (cfg.integrationTestMode == 'job') {
                                new JobManager(this, cfg).triggerIntegrationJob(imageTag)
                            } else if (cfg.integrationTestCommand) {
                                sh "${cfg.integrationTestCommand} ${cfg.registry}/${imageTag}"
                            } else {
                                echo 'No integration test command configured, skipping.'
                            }
                        }

                        // Only promote to the floating ':latest' tag once integration tests pass.
                        stage('Promote Image') {
                            new ArtifactoryPublisher(this, cfg).promote(imageTag)
                        }
                    } else {
                        echo "Push disabled for branch '${env.BRANCH_NAME}' - built and scanned image was not published."
                    }
                }
            }
            currentBuild.result = 'SUCCESS'
        } catch (err) {
            currentBuild.result = 'FAILURE'
            throw err
        } finally {
            new Notifier(this, cfg ?: [:]).notify(currentBuild.result ?: 'UNKNOWN')
            if (imageTag && cfg) {
                sh "docker rmi ${cfg.registry}/${imageTag} || true"
            }
            cleanWs()
        }
    }
}
