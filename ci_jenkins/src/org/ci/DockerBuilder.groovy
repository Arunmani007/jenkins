package org.ci

class DockerBuilder implements Serializable {
    def script
    Map cfg

    DockerBuilder(script, Map cfg) {
        this.script = script
        this.cfg = cfg
    }

    void lint() {
        script.sh """
            if command -v hadolint >/dev/null 2>&1; then
                hadolint ${cfg.dockerfilePath}
            else
                echo 'hadolint not installed on this agent, skipping Dockerfile lint'
            fi
        """
    }

    void build(String imageTag) {
        script.sh "docker build -f ${cfg.dockerfilePath} -t ${cfg.registry}/${imageTag} ${cfg.buildContext}"
    }
}
