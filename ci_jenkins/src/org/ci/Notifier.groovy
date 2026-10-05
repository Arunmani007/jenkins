package org.ci

class Notifier implements Serializable {
    def script
    Map cfg

    Notifier(script, Map cfg) {
        this.script = script
        this.cfg = cfg
    }

    void notify(String result) {
        if (!cfg?.notifyChannel) {
            return
        }
        try {
            script.slackSend(
                channel: cfg.notifyChannel,
                color: result == 'SUCCESS' ? 'good' : 'danger',
                message: "Pipeline *${script.env.JOB_NAME}* #${script.env.BUILD_NUMBER} finished with status: *${result}*\n${script.env.BUILD_URL}"
            )
        } catch (ignored) {
            script.echo "Notification failed: ${ignored.message}"
        }
    }
}
