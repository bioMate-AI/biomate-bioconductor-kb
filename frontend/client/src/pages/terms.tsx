import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"

export default function TermsPage() {
  return (
    <div className="min-h-screen bg-background py-12">
      <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="mb-8">
          <h1 className="text-4xl font-bold mb-4">Terms of Service</h1>
          <p className="text-muted-foreground">Last updated: March 10, 2026</p>
        </div>

        <div className="prose prose-lg dark:prose-invert max-w-none space-y-8">
          <Card>
            <CardHeader>
              <CardTitle>1. Acceptance of Terms</CardTitle>
            </CardHeader>
            <CardContent className="text-muted-foreground">
              <p>
                By accessing and using BioMate ("Service"), you accept and agree to be bound by these Terms of Service ("Terms").
                If you do not agree to these Terms, do not use the Service.
              </p>
              <p className="mt-4">
                We reserve the right to modify these Terms at any time. Continued use of the Service after changes constitutes
                acceptance of the modified Terms.
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>2. Account Registration</CardTitle>
            </CardHeader>
            <CardContent className="text-muted-foreground space-y-4">
              <p>To use certain features of the Service, you must register for an account:</p>
              <ul className="list-disc pl-6 mt-2 space-y-1">
                <li>You must provide accurate and complete information</li>
                <li>You are responsible for maintaining the security of your account</li>
                <li>You must be at least 18 years old to create an account</li>
                <li>You are responsible for all activities that occur under your account</li>
                <li>You must notify us immediately of any unauthorized access</li>
              </ul>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>3. Acceptable Use</CardTitle>
            </CardHeader>
            <CardContent className="text-muted-foreground space-y-4">
              <p>You agree to use the Service only for lawful purposes and in accordance with these Terms. You agree NOT to:</p>
              <ul className="list-disc pl-6 mt-2 space-y-1">
                <li>Violate any applicable laws or regulations</li>
                <li>Infringe on intellectual property rights of others</li>
                <li>Upload malicious code or viruses</li>
                <li>Attempt to gain unauthorized access to the Service</li>
                <li>Interfere with or disrupt the Service</li>
                <li>Use the Service for any illegal or unethical research</li>
                <li>Share your account credentials with others</li>
                <li>Scrape or crawl the Service without permission</li>
              </ul>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>4. Intellectual Property</CardTitle>
            </CardHeader>
            <CardContent className="text-muted-foreground space-y-4">
              <div>
                <h4 className="font-semibold text-foreground mb-2">4.1 Our Content</h4>
                <p>
                  The Service and its original content, features, and functionality are owned by BioMate and are protected by
                  international copyright, trademark, and other intellectual property laws.
                </p>
              </div>

              <div>
                <h4 className="font-semibold text-foreground mb-2">4.2 Your Content</h4>
                <p>
                  You retain all rights to the research data and workflows you create using the Service. By using the Service,
                  you grant us a limited license to use, store, and process your content solely to provide the Service.
                </p>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>5. Subscription and Payment</CardTitle>
            </CardHeader>
            <CardContent className="text-muted-foreground space-y-4">
              <div>
                <h4 className="font-semibold text-foreground mb-2">5.1 Free Trial</h4>
                <p>
                  We offer a 14-day free trial for paid plans. You will not be charged during the trial period. After the trial,
                  your subscription will automatically begin unless you cancel.
                </p>
              </div>

              <div>
                <h4 className="font-semibold text-foreground mb-2">5.2 Billing</h4>
                <ul className="list-disc pl-6 space-y-1">
                  <li>Subscriptions are billed monthly or annually in advance</li>
                  <li>All fees are non-refundable except as required by law</li>
                  <li>We may change pricing with 30 days notice</li>
                  <li>Failure to pay may result in service suspension</li>
                </ul>
              </div>

              <div>
                <h4 className="font-semibold text-foreground mb-2">5.3 Cancellation</h4>
                <p>
                  You may cancel your subscription at any time. Cancellation takes effect at the end of your current billing period.
                  You will retain access to paid features until then.
                </p>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>6. Data and Privacy</CardTitle>
            </CardHeader>
            <CardContent className="text-muted-foreground space-y-4">
              <p>
                Your use of the Service is also governed by our Privacy Policy. By using the Service, you consent to the
                collection and use of information as described in our Privacy Policy.
              </p>
              <ul className="list-disc pl-6 space-y-1">
                <li>You retain all rights to the research data and results you generate using the Service</li>
                <li>We do not use your research data to train or fine-tune any AI model without your explicit consent</li>
                <li>We implement industry-standard security measures including encryption at rest (AES-256) and in transit (TLS 1.2+)</li>
                <li>You are responsible for backing up your data</li>
                <li>We may collect anonymized, aggregate usage metrics (e.g. workflow run durations, step completion rates) to improve the Service. These metrics contain no research data and cannot be attributed to any individual or institution.</li>
              </ul>
              <div>
                <h4 className="font-semibold text-foreground mb-2">6.1 Pilot Study Participants</h4>
                <p>
                  If you are participating in a BioMate pilot evaluation study, you may be invited to complete
                  voluntary in-product feedback surveys after each workflow run and at the end of the pilot period.
                  Your individual survey responses will not be shared with any third party or attributed to you
                  by name. Aggregate, anonymised pilot evaluation results may be used in academic publications
                  or product improvement reports, with your institution's prior consent.
                  Participation in surveys is entirely voluntary and does not affect your access to the Service.
                </p>
              </div>
              <div>
                <h4 className="font-semibold text-foreground mb-2">6.2 Data Deletion</h4>
                <p>
                  You may request deletion of your account and all associated data at any time by contacting
                  legal@biomate.ai. Raw research files uploaded to BioMate-managed storage will be permanently
                  deleted within 14 calendar days of your request. We will provide written confirmation of deletion.
                </p>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>7. Disclaimers and Limitations</CardTitle>
            </CardHeader>
            <CardContent className="text-muted-foreground space-y-4">
              <div>
                <h4 className="font-semibold text-foreground mb-2">7.1 Service "As Is"</h4>
                <p>
                  THE SERVICE IS PROVIDED "AS IS" WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING
                  BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT.
                </p>
              </div>

              <div>
                <h4 className="font-semibold text-foreground mb-2">7.2 Research Use</h4>
                <p>
                  The Service is intended for research purposes. Results generated by the Service should be independently
                  verified. We make no guarantees about the accuracy or reliability of AI-generated insights.
                </p>
              </div>

              <div>
                <h4 className="font-semibold text-foreground mb-2">7.3 Limitation of Liability</h4>
                <p>
                  TO THE MAXIMUM EXTENT PERMITTED BY LAW, BIOMATE SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL,
                  SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES ARISING OUT OF YOUR USE OF THE SERVICE.
                </p>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>8. Termination</CardTitle>
            </CardHeader>
            <CardContent className="text-muted-foreground">
              <p>We may terminate or suspend your account and access to the Service:</p>
              <ul className="list-disc pl-6 mt-2 space-y-1">
                <li>For violation of these Terms</li>
                <li>For fraudulent or illegal activities</li>
                <li>At your request</li>
                <li>For non-payment</li>
              </ul>
              <p className="mt-4">
                Upon termination, your right to use the Service will immediately cease. You may export your data before
                termination. We may delete your data 30 days after termination.
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>9. Indemnification</CardTitle>
            </CardHeader>
            <CardContent className="text-muted-foreground">
              <p>
                You agree to indemnify and hold harmless BioMate from any claims, damages, losses, liabilities, and expenses
                arising out of your use of the Service or violation of these Terms.
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>10. Governing Law</CardTitle>
            </CardHeader>
            <CardContent className="text-muted-foreground">
              <p>
                These Terms are governed by the laws of the State of Texas, United States, without regard to conflict
                of law principles. Any disputes shall be resolved in the state or federal courts located in Texas.
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>11. Changes to Service</CardTitle>
            </CardHeader>
            <CardContent className="text-muted-foreground">
              <p>
                We reserve the right to modify or discontinue the Service at any time, with or without notice. We will not
                be liable to you or any third party for any modification, suspension, or discontinuation of the Service.
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>12. Contact Information</CardTitle>
            </CardHeader>
            <CardContent className="text-muted-foreground">
              <p>For questions about these Terms, please contact us:</p>
              <ul className="mt-2 space-y-1">
                <li>Email: legal@biomate.ai</li>
                <li>Website: biomate.ai</li>
              </ul>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  )
}
