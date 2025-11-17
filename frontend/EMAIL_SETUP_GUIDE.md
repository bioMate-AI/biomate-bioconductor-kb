# Email Service Setup Guide

## Current Status
- ❌ EMAIL_HOST: NOT SET
- ❌ EMAIL_USER: NOT SET
- ❌ EMAIL_PASS: NOT SET
- ✓ EMAIL_PORT: 587 (default)
- ✓ EMAIL_FROM: noreply@biomate.dev

## Required For
- Email verification after registration
- Password reset emails
- Trial expiration warnings
- Payment notifications
- Workflow completion alerts
- Security alerts

## Option 1: AWS SES (Recommended for Production)

### Setup Steps

#### 1. Create AWS SES Account
```bash
# Login to AWS Console
# Go to: Simple Email Service (SES)
```

#### 2. Verify Domain
```bash
# In AWS SES → Domains → Verify a New Domain
Domain: biomate.com (or your domain)

# Add DNS records (provided by AWS):
TXT record for domain verification
CNAME records for DKIM
```

####3. Request Production Access
```bash
# By default, SES is in sandbox mode (can only send to verified emails)
# Request production access:
# SES → Account Dashboard → Request Production Access

# Provide:
- Use case description
- Expected send volume
- Bounce/complaint handling process
```

#### 4. Create SMTP Credentials
```bash
# SES → SMTP Settings → Create My SMTP Credentials
# Save:
- SMTP Username
- SMTP Password
- SMTP Endpoint: email-smtp.us-east-1.amazonaws.com
```

#### 5. Configure DNS Records
```dns
# SPF (Sender Policy Framework)
TXT @ "v=spf1 include:amazonses.com ~all"

# DKIM (DomainKeys Identified Mail)
# AWS provides these - add to DNS:
CNAME <selector>._domainkey.<domain> <value>._domainkey.amazonses.com

# DMARC (Domain-based Message Authentication)
TXT _dmarc "v=DMARC1; p=quarantine; rua=mailto:postmaster@biomate.com"
```

#### 6. Update Environment Variables
```bash
# Edit: /home/yzhang/biomate/frontend/.env

EMAIL_HOST=email-smtp.us-east-1.amazonaws.com
EMAIL_PORT=587
EMAIL_SECURE=false  # Use STARTTLS
EMAIL_USER=your_smtp_username
EMAIL_PASS=your_smtp_password
EMAIL_FROM=noreply@biomate.com
```

### AWS SES Pricing
- Free: 62,000 emails/month (if sending from EC2)
- Paid: $0.10 per 1,000 emails
- Very cost-effective for most use cases

---

## Option 2: SendGrid (Alternative)

### Setup Steps

#### 1. Create SendGrid Account
```bash
# Visit: https://signup.sendgrid.com/
```

#### 2. Verify Domain
```bash
# Settings → Sender Authentication → Authenticate Your Domain
# Add DNS records provided by SendGrid
```

#### 3. Create API Key
```bash
# Settings → API Keys → Create API Key
# Permissions: Full Access (or Mail Send only)
# Save the API key
```

#### 4. Update Environment Variables
```bash
# SendGrid uses API key (not SMTP password)
EMAIL_HOST=smtp.sendgrid.net
EMAIL_PORT=587
EMAIL_SECURE=false
EMAIL_USER=apikey  # Literally the string "apikey"
EMAIL_PASS=your_sendgrid_api_key
EMAIL_FROM=noreply@biomate.com
```

### SendGrid Pricing
- Free: 100 emails/day
- Essentials: $19.95/month (50K emails/month)
- Pro: $89.95/month (1.5M emails/month)

---

## Option 3: Mailgun (Alternative)

#### Setup
```bash
# Visit: https://signup.mailgun.com/
# Verify domain
# Get SMTP credentials

EMAIL_HOST=smtp.mailgun.org
EMAIL_PORT=587
EMAIL_SECURE=false
EMAIL_USER=postmaster@your-domain.mailgun.org
EMAIL_PASS=your_smtp_password
EMAIL_FROM=noreply@biomate.com
```

---

## Testing Email Service

### 1. Restart Server
```bash
cd /home/yzhang/biomate/frontend
npm run dev
```

### 2. Test Sending
```bash
# Test forgot password endpoint (sends email):
curl -X POST http://localhost:5000/api/auth/forgot-password \
  -H "Content-Type: application/json" \
  -d '{"email":"your-test-email@gmail.com"}'

# Should return success (not "email not configured")
```

### 3. Check Inbox
- Check your test email inbox
- Look for password reset email
- Verify from address, subject, content

### 4. Test All Email Types

Create test script:
```javascript
// test-emails.js
const nodemailer = require('nodemailer');

const transporter = nodemailer.createTransport({
  host: process.env.EMAIL_HOST,
  port: parseInt(process.env.EMAIL_PORT),
  secure: process.env.EMAIL_SECURE === 'true',
  auth: {
    user: process.env.EMAIL_USER,
    pass: process.env.EMAIL_PASS
  }
});

// Test email
async function testEmail() {
  const info = await transporter.sendMail({
    from: process.env.EMAIL_FROM,
    to: 'your-test-email@gmail.com',
    subject: 'Biomate Email Test',
    text: 'If you receive this, email service is configured correctly!',
    html: '<p>If you receive this, email service is <strong>configured correctly</strong>!</p>'
  });

  console.log('Message sent:', info.messageId);
}

testEmail().catch(console.error);
```

Run test:
```bash
cd /home/yzhang/biomate/frontend
node test-emails.js
```

---

## Email Templates Needed

Create these templates in `/home/yzhang/biomate/frontend/server/email-templates/`:

### 1. welcome.html
Sent after registration
- Welcome message
- Quick start guide
- Support links

### 2. verify-email.html
Email verification
- Verification link (expires in 24h)
- Resend option

### 3. password-reset.html
Password reset request
- Reset link (expires in 1h)
- Security note

### 4. trial-expiring.html
2 days before trial ends
- Trial end date
- Upgrade CTA
- Current plan details

### 5. payment-succeeded.html
After successful payment
- Invoice details
- Receipt
- Next billing date

### 6. payment-failed.html
When payment fails
- Error message
- Update payment method link
- Grace period info

### 7. subscription-canceled.html
When user cancels
- Confirmation
- Reactivation option
- Data retention policy

### 8. workflow-complete.html
After workflow finishes
- Workflow name
- Results summary
- View results link

### 9. workflow-failed.html
When workflow errors
- Error message
- Troubleshooting steps
- Support link

### 10. security-alert.html
Suspicious activity
- Activity details (location, device)
- Secure account link
- Support contact

---

## Implementation Files

- **Email Service**: `frontend/server/email-service.ts`
- **Email Templates**: `frontend/server/email-templates/` (create this directory)
- **Usage**: Various places in routes.ts

---

## Testing Checklist

- [ ] SMTP connection works
- [ ] Can send test email
- [ ] Email appears in inbox (not spam)
- [ ] From address correct
- [ ] Links in email work
- [ ] Email formatting looks good
- [ ] All email templates exist
- [ ] Password reset email sends
- [ ] Email verification sends
- [ ] Trial warning email sends
- [ ] Payment emails send

---

## Troubleshooting

### "Email not configured" error
```bash
# Check env variables are set:
grep EMAIL /home/yzhang/biomate/frontend/.env

# Restart server after updating
```

### Emails go to spam
```bash
# Configure SPF, DKIM, DMARC records
# Warm up sender reputation (gradually increase volume)
# Use reputable email service (AWS SES, SendGrid)
# Avoid spam trigger words in subject/body
```

### SMTP connection timeout
```bash
# Check firewall allows port 587
# Try port 465 (SSL) instead
# Verify SMTP credentials
# Check service status
```

### Rate limiting
```bash
# AWS SES: 14 emails/second by default
# SendGrid: Based on plan
# Implement retry logic with exponential backoff
```

---

## Security Best Practices

1. **Use STARTTLS** (port 587, not plain 25)
2. **Store credentials securely** (.env, not in code)
3. **Validate email addresses** before sending
4. **Rate limit** password reset requests
5. **Use signed links** for email verification (with expiration)
6. **Log email sends** for audit trail
7. **Handle bounces** and unsubscribes
8. **GDPR compliance** - allow users to opt out

---

## Monitoring

Track these metrics:
- Email send success rate
- Bounce rate (should be < 5%)
- Complaint rate (should be < 0.1%)
- Open rates (for analytics)
- Click rates (for CTA effectiveness)

AWS SES provides these in CloudWatch.
SendGrid has built-in analytics dashboard.

---

## Next Steps After Setup

1. Create all 10 email templates
2. Test each template
3. Set up bounce handling
4. Configure complaint handling
5. Implement email preferences (let users choose which emails they get)
6. Add unsubscribe links (required by law)
7. Monitor deliverability
8. Set up email queue for high volume (use Redis + Bull)
