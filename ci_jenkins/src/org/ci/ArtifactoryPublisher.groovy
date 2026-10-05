package org.ci

// Publishes images to Artifactory's Docker registry. Credentials are bound via
// Jenkins credentials store and never written to logs or disk.
class ArtifactoryPublisher implements Serializable {
    def script
    Map cfg

    ArtifactoryPublisher(script, Map cfg) {
        this.script = script
        this.cfg = cfg
    }

    void push(String imageTag) {
        withLogin {
            script.sh "docker push ${cfg.registry}/${imageTag}"
        }
    }

    void promote(String imageTag) {
        if (!(script.env.BRANCH_NAME in ['main', 'master'])) {
            script.echo "Skipping promotion to 'latest' on branch ${script.env.BRANCH_NAME}"
            return
        }
        String latestTag = "${cfg.registry}/${cfg.imageName}:latest"
        withLogin {
            script.sh """
                docker tag ${cfg.registry}/${imageTag} ${latestTag}
                docker push ${latestTag}
            """
        }
    }

    private void withLogin(Closure body) {
        script.withCredentials([script.usernamePassword(
            credentialsId: cfg.artifactoryCredentialsId,
            usernameVariable: 'ARTIFACTORY_USER',
            passwordVariable: 'ARTIFACTORY_PASS'
        )]) {
            script.sh 'echo $ARTIFACTORY_PASS | docker login ' + cfg.registry + ' -u $ARTIFACTORY_USER --password-stdin'
            body()
            script.sh "docker logout ${cfg.registry}"
        }
    }
}
