import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"

export default function PrivacyPage() {
  return (
    <div className="min-h-screen bg-background py-12">
      <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="mb-8">
          <h1 className="text-4xl font-bold mb-4">Privacy Policy</h1>
          <p className="text-muted-foreground">Last updated: April 28, 2026</p>
        </div>

        <div className="prose prose-lg dark:prose-invert max-w-none space-y-8">
          <Card>
            <CardHeader>
              <CardTitle>1. Introduction</CardTitle>
            </CardHeader>
            <CardContent className="text-muted-foreground">
              <p>
                BioMate ("we," "our," or "us") is committed to protecting your privacy. This Privacy Policy explains how we collect,
                use, disclose, and safeguard your information when you use our platform and services.
              </p>
              <p className="mt-4">
                By using BioMate, you agree to the collection and use of information in accordance with this policy.
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>2. Information We Collect</CardTitle>
            </CardHeader>
            <CardContent className="text-muted-foreground space-y-4">
              <div>
                <h4 className="font-semibold text-foreground mb-2">2.1 Personal Information</h4>
                <p>We collect information that you provide directly to us, including:</p>
                <ul className="list-disc pl-6 mt-2 space-y-1">
                  <li>Name and contact information (email address, phone number)</li>
                  <li>Account credentials (username and password)</li>
                  <li>Institutional affiliation</li>
                  <li>Billing and payment information</li>
                  <li>Research data and workflows you create</li>
                </ul>
              </div>

              <div>
                <h4 className="font-semibold text-foreground mb-2">2.2 Usage Information</h4>
                <p>We automatically collect certain information about your device and how you interact with our platform:</p>
                <ul className="list-disc pl-6 mt-2 space-y-1">
                  <li>IP address and device identifiers</li>
                  <li>Browser type and version</li>
                  <li>Pages visited and features used</li>
                  <li>Time and date of visits</li>
                  <li>Performance and error logs</li>
                </ul>
              </div>

              <div>
                <h4 className="font-semibold text-foreground mb-2">2.3 Research Data</h4>
                <p>
                  We process research data that you upload or generate using our platform. This may include genomic data,
                  proteomic data, and other biomedical research information.
                </p>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>3. How We Use Your Information</CardTitle>
            </CardHeader>
            <CardContent className="text-muted-foreground">
              <p>We use the collected information for the following purposes:</p>
              <ul className="list-disc pl-6 mt-2 space-y-1">
                <li>Provide, maintain, and improve our services</li>
                <li>Process your transactions and send related information</li>
                <li>Send technical notices, updates, and support messages</li>
                <li>Respond to your comments and questions</li>
                <li>Develop new features and services</li>
                <li>Monitor and analyze usage patterns and trends</li>
                <li>Detect, prevent, and address technical issues and security threats</li>
                <li>Comply with legal obligations</li>
              </ul>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>4. Data Security</CardTitle>
            </CardHeader>
            <CardContent className="text-muted-foreground space-y-4">
              <p>
                We implement industry-standard security measures to protect your information:
              </p>
              <ul className="list-disc pl-6 mt-2 space-y-1">
                <li>Encryption in transit (TLS 1.2+) and at rest (AES-256)</li>
                <li>PHI detection and automatic stripping before AI processing</li>
                <li>Regular security audits and penetration testing</li>
                <li>Access controls and authentication mechanisms</li>
                <li>Secure data centers with physical security measures</li>
                <li>Regular backups and disaster recovery procedures</li>
              </ul>
              <p className="mt-4">
                However, no method of transmission over the Internet is 100% secure, and we cannot guarantee absolute security.
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>5. Data Sharing and Disclosure</CardTitle>
            </CardHeader>
            <CardContent className="text-muted-foreground space-y-4">
              <p>We do not sell your personal information. We may share your information in the following circumstances:</p>
              <ul className="list-disc pl-6 mt-2 space-y-1">
                <li><strong>With your consent:</strong> When you explicitly authorize us to share information</li>
                <li><strong>Service providers:</strong> Third-party vendors who perform services on our behalf (e.g., hosting, analytics)</li>
                <li><strong>Collaborators:</strong> Other users you choose to collaborate with on workflows</li>
                <li><strong>Legal requirements:</strong> When required by law or to protect our rights</li>
                <li><strong>Business transfers:</strong> In connection with a merger, acquisition, or sale of assets</li>
              </ul>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>6. Your Rights and Choices</CardTitle>
            </CardHeader>
            <CardContent className="text-muted-foreground">
              <p>You have the following rights regarding your personal information:</p>
              <ul className="list-disc pl-6 mt-2 space-y-1">
                <li><strong>Access:</strong> Request a copy of your personal information</li>
                <li><strong>Correction:</strong> Request correction of inaccurate information</li>
                <li><strong>Deletion:</strong> Request deletion of your information</li>
                <li><strong>Portability:</strong> Request transfer of your data to another service</li>
                <li><strong>Opt-out:</strong> Unsubscribe from marketing communications</li>
              </ul>
              <p className="mt-4">
                To exercise these rights, contact us at privacy@biomate.ai
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>7. HIPAA Compliance</CardTitle>
            </CardHeader>
            <CardContent className="text-muted-foreground space-y-4">
              <p>
                BioMate is designed to support HIPAA-compliant research workflows. Our platform incorporates the
                following safeguards regardless of customer tier:
              </p>
              <ul className="list-disc pl-6 mt-2 space-y-1">
                <li>
                  <strong>PHI detection and stripping:</strong> All messages are scanned for protected health
                  information using pattern matching (names, dates, MRNs, SSNs, phone numbers, and other
                  HIPAA-defined identifiers) before reaching AI systems. Detected PHI is automatically
                  redacted to prevent inadvertent disclosure.
                </li>
                <li>
                  <strong>Audit logging:</strong> Access to PHI and sensitive resources is logged per
                  HIPAA §164.312, with tamper-evident records of who accessed what and when.
                </li>
                <li>
                  <strong>Business Associate Agreement (BAA):</strong> Enterprise customers handling PHI
                  may request a BAA. Contact our sales team to initiate a BAA and receive access to
                  dedicated HIPAA-compliant infrastructure.
                </li>
              </ul>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>8. International Data Transfers</CardTitle>
            </CardHeader>
            <CardContent className="text-muted-foreground">
              <p>
                Your information may be transferred to and processed in countries other than your country of residence.
                We ensure appropriate safeguards are in place for such transfers in compliance with applicable data protection laws.
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>9. Children's Privacy</CardTitle>
            </CardHeader>
            <CardContent className="text-muted-foreground">
              <p>
                Our services are not directed to individuals under 18. We do not knowingly collect personal information from children.
                If you become aware that a child has provided us with personal information, please contact us.
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>10. Changes to This Policy</CardTitle>
            </CardHeader>
            <CardContent className="text-muted-foreground">
              <p>
                We may update this Privacy Policy from time to time. We will notify you of any changes by posting the new policy
                on this page and updating the "Last updated" date. Continued use of our services after changes constitutes acceptance.
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>11. Contact Us</CardTitle>
            </CardHeader>
            <CardContent className="text-muted-foreground">
              <p>If you have questions about this Privacy Policy, please contact us:</p>
              <ul className="mt-2 space-y-1">
                <li>Email: privacy@biomate.ai</li>
                <li>Address: BioMate Inc., 123 Research Blvd, San Francisco, CA 94103</li>
              </ul>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  )
}
