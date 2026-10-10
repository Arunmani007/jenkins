package org.ci

import hudson.model.Cause
import hudson.model.User
import jenkins.model.Jenkins

// Scans the built image for vulnerabilities (Trivy) and container best-practice
// issues (Dockle), archives reports, and fails the build based on configured policy.
class SecurityScanner implements Serializable {
    def script
    Map cfg

    SecurityScanner(script, Map cfg) {
        this.script = script
        this.cfg = cfg
    }

    void scan(String imageTag, boolean bypassRequested = false) {
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

        // Re-checked server-side so a dev can't bypass the gate just by ticking the
        // build parameter themselves - only users with Jenkins ADMINISTER can.
        boolean bypassGranted = bypassRequested && isAdmin()
        if (bypassRequested && !bypassGranted) {
            script.echo "BYPASS_SECURITY_SCAN was requested but '${currentUserId() ?: 'unknown user'}' lacks Administer permission - vulnerability gate still enforced."
        }

        if (cfg.failOnVulnerabilities && !bypassGranted) {
            int exitCode = script.sh(
                script: "trivy image --exit-code 1 --severity ${cfg.vulnerabilitySeverity} ${fullImage}",
                returnStatus: true
            )
            if (exitCode != 0) {
                script.error("Image ${fullImage} failed vulnerability scan (severity: ${cfg.vulnerabilitySeverity}). See reports/trivy-report.txt")
            }
        } else if (bypassGranted) {
            script.echo "Vulnerability gate bypassed by admin '${currentUserId()}' via BYPASS_SECURITY_SCAN - review reports/trivy-report.txt manually."
        }
    }

    private boolean isAdmin() {
        String userId = currentUserId()
        if (!userId) {
            return false
        }
        def auth = User.get(userId, false)?.impersonate2()
        return auth != null && Jenkins.get().hasPermission2(auth, Jenkins.ADMINISTER)
    }

    private String currentUserId() {
        return script.currentBuild.rawBuild.getCause(Cause.UserIdCause)?.userId
    }
}
