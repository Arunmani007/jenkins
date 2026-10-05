package org.ci

// Scans the built image for vulnerabilities (Trivy) and container best-practice
// issues (Dockle), archives reports, and fails the build based on configured policy.
class SecurityScanner implements Serializable {
    def script
    Map cfg

    SecurityScanner(script, Map cfg) {
        this.script = script
        this.cfg = cfg
    }

    void scan(String imageTag) {
        String fullImage = "${cfg.registry}/${imageTag}"
        script.sh 'mkdir -p reports'

        script.sh """
            trivy image --exit-code 0 --severity ${cfg.vulnerabilitySeverity} \
                --format json -o reports/trivy-report.json ${fullImage}
            trivy image --exit-code 0 --severity ${cfg.vulnerabilitySeverity} \
                --format table ${fullImage} | tee reports/trivy-report.txt
        """

        script.sh """
            if command -v dockle >/dev/null 2>&1; then
                dockle --exit-code 0 -o reports/dockle-report.txt ${fullImage}
            else
                echo 'dockle not installed on this agent, skipping container quality scan'
            fi
        """

        script.archiveArtifacts artifacts: 'reports/*', allowEmptyArchive: true

        if (cfg.failOnVulnerabilities) {
            int exitCode = script.sh(
                script: "trivy image --exit-code 1 --severity ${cfg.vulnerabilitySeverity} ${fullImage}",
                returnStatus: true
            )
            if (exitCode != 0) {
                script.error("Image ${fullImage} failed vulnerability scan (severity: ${cfg.vulnerabilitySeverity}). See reports/trivy-report.txt")
            }
        }
    }
}
