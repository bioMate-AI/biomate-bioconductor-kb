//
// This file holds useful functions
// It is based on nf-core's NfcoreTemplate
//


class TalusTemplate {
    //
    // Construct and send completion email
    //
    // Returns
    // -------
    // str
    //     The HTML email body.
    public static email(workflow, params) {
        // Set the email subject:
        def subject = "[$workflow.manifest.name] SUCCESS: ${workflow.runName}"
        if (!workflow.success) {
            subject = "[$workflow.manifest.name] FAILED ${workflow.runName}"
        }

        // Used in ../assets/email_template.html
        def email_fields = [:]
        email_fields['started']      = workflow.start
        email_fields['dateComplete'] = workflow.complete
        email_fields['runName']      = workflow.runName
        email_fields['uuid']         = workflow.sessionId
        email_fields['success']      = workflow.success
        email_fields['duration']     = workflow.duration
        email_fields['exitStatus']   = workflow.exitStatus
        email_fields['errorMessage'] = (workflow.errorMessage ?: 'None')
        email_fields['errorReport']  = (workflow.errorReport ?: 'None')
        email_fields['commandLine']  = workflow.commandLine
        email_fields['projectDir']   = workflow.projectDir

        // Complete the email template:
        def engine = new groovy.text.GStringTemplateEngine()
        def html_path = "${workflow.projectDir}/assets/email_template.html"
        def html_file = new File(html_path)
        def html_template = engine.createTemplate(html_file).make(email_fields)
        def email_html = html_template.toString()
        return [subject, email_html]
    }
}
