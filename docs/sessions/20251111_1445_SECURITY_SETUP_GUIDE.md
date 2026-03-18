# Security Setup Guide - Production Deployment
**Version:** 1.0
**Date:** 2025-11-11
**Audience:** DevOps, Security Engineers

---

## Overview

This guide provides step-by-step instructions to implement SOC 2 and HIPAA compliant security controls for BioMate AI before production deployment.

**⚠️ CRITICAL:** All steps marked with 🔴 must be completed before launching to production.

---

## Pre-Deployment Security Checklist

### Phase 1: Environment and Secrets Management (Week 1)

#### 🔴 Step 1.1: Generate Encryption Keys

```bash
# Generate encryption key for data at rest
node -e "console.log(crypto.randomBytes(32).toString('base64'))"
# Save output to ENCRYPTION_KEY

# Generate JWT secret
node -e "console.log(crypto.randomBytes(64).toString('base64'))"
# Save output to JWT_SECRET

# Generate session secret
node -e "console.log(crypto.randomBytes(64).toString('base64'))"
# Save output to SESSION_SECRET
```

#### 🔴 Step 1.2: Set Up AWS Secrets Manager (Recommended)

```bash
# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Configure AWS CLI
aws configure

# Create secrets in Secrets Manager
aws secretsmanager create-secret \
  --name biomate/production/encryption-key \
  --secret-string "$(node -e 'console.log(crypto.randomBytes(32).toString(\"base64\"))')"

aws secretsmanager create-secret \
  --name biomate/production/jwt-secret \
  --secret-string "$(node -e 'console.log(crypto.randomBytes(64).toString(\"base64\"))')"

aws secretsmanager create-secret \
  --name biomate/production/session-secret \
  --secret-string "$(node -e 'console.log(crypto.randomBytes(64).toString(\"base64\"))')"

aws secretsmanager create-secret \
  --name biomate/production/anthropic-api-key \
  --secret-string "your-anthropic-api-key"
```

#### 🔴 Step 1.3: Update Environment Variables

Create `/home/biomate/.env.production`:

```bash
# NEVER commit this file to git!
# In production, use AWS Secrets Manager instead

NODE_ENV=production

# Security Keys (load from Secrets Manager)
ENCRYPTION_KEY=<generated-key>
JWT_SECRET=<generated-secret>
SESSION_SECRET=<generated-secret>

# API Keys (load from Secrets Manager)
ANTHROPIC_API_KEY=<your-key>
OPENAI_API_KEY=<your-key>

# Database (RDS)
DATABASE_URL=postgresql://username:password@rds-endpoint:5432/biomate_prod?sslmode=require

# Redis (ElastiCache)
REDIS_URL=rediss://redis-endpoint:6379
REDIS_TLS=true

# Session Configuration
SESSION_SECRET=<generated-secret>
SESSION_TIMEOUT=15  # 15 minutes (HIPAA requirement)

# CORS Configuration
CORS_ORIGINS=https://biomate.ai,https://www.biomate.ai

# S3 Configuration
AWS_REGION=us-west-2
S3_BUCKET=biomate-user-data
S3_BACKUP_BUCKET=biomate-backups

# Email Configuration
SMTP_HOST=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USER=apikey
SMTP_PASS=<your-sendgrid-key>
EMAIL_FROM=noreply@biomate.ai

# Stripe (if using)
STRIPE_SECRET_KEY=<your-stripe-secret>
STRIPE_WEBHOOK_SECRET=<your-webhook-secret>

# Monitoring
SENTRY_DSN=<your-sentry-dsn>
```

#### Step 1.4: Secure File Permissions

```bash
# Set restrictive permissions on .env files
chmod 600 /home/biomate/.env.production
chown biomate:biomate /home/biomate/.env.production

# Ensure .env is in .gitignore
echo ".env*" >> /home/biomate/.gitignore
echo "!.env.example" >> /home/biomate/.gitignore
```

---

### Phase 2: HTTPS/TLS Configuration (Week 1)

#### 🔴 Step 2.1: Obtain SSL Certificate

**Option A: Let's Encrypt (Recommended for most)**

```bash
# Install certbot
sudo apt-get update
sudo apt-get install certbot python3-certbot-nginx

# Obtain certificate
sudo certbot --nginx -d biomate.ai -d www.biomate.ai

# Test auto-renewal
sudo certbot renew --dry-run
```

**Option B: AWS Certificate Manager (for load balancers)**

```bash
# Request certificate
aws acm request-certificate \
  --domain-name biomate.ai \
  --subject-alternative-names www.biomate.ai \
  --validation-method DNS \
  --region us-west-2

# Add DNS validation records
# (follow AWS console instructions)
```

#### 🔴 Step 2.2: Configure Nginx with TLS 1.3

Create `/etc/nginx/sites-available/biomate.conf`:

```nginx
# Redirect HTTP to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name biomate.ai www.biomate.ai;

    return 301 https://$server_name$request_uri;
}

# HTTPS server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name biomate.ai www.biomate.ai;

    # SSL Certificate
    ssl_certificate /etc/letsencrypt/live/biomate.ai/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/biomate.ai/privkey.pem;

    # TLS 1.3 only (strongest security)
    ssl_protocols TLSv1.3;
    ssl_prefer_server_ciphers off;

    # HSTS (force HTTPS for 1 year)
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    # Security headers (defense in depth)
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Proxy to Node.js application
    location / {
        proxy_pass http://localhost:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    # Increase upload limit for datasets
    client_max_body_size 500M;
}
```

```bash
# Enable site
sudo ln -s /etc/nginx/sites-available/biomate.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

---

### Phase 3: Database Security (Week 2)

#### 🔴 Step 3.1: Enable PostgreSQL Encryption at Rest

**AWS RDS:**

```bash
# Create encrypted RDS instance
aws rds create-db-instance \
  --db-instance-identifier biomate-prod \
  --db-instance-class db.t3.medium \
  --engine postgres \
  --engine-version 15.4 \
  --master-username biomate_admin \
  --master-user-password <secure-password> \
  --allocated-storage 100 \
  --storage-encrypted \
  --kms-key-id alias/aws/rds \
  --backup-retention-period 30 \
  --enable-cloudwatch-logs-exports '["postgresql"]' \
  --storage-type gp3
```

#### 🔴 Step 3.2: Configure Database SSL

```sql
-- Require SSL for all connections
ALTER SYSTEM SET ssl = on;
ALTER SYSTEM SET ssl_min_protocol_version = 'TLSv1.3';

-- Create read-only user for reporting
CREATE ROLE biomate_readonly;
GRANT CONNECT ON DATABASE biomate_prod TO biomate_readonly;
GRANT USAGE ON SCHEMA public TO biomate_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO biomate_readonly;
```

#### 🔴 Step 3.3: Enable Audit Logging

```sql
-- Enable PostgreSQL audit logging
ALTER SYSTEM SET log_connections = on;
ALTER SYSTEM SET log_disconnections = on;
ALTER SYSTEM SET log_duration = on;
ALTER SYSTEM SET log_statement = 'all';
ALTER SYSTEM SET log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h ';

-- Reload configuration
SELECT pg_reload_conf();
```

---

### Phase 4: Application Security (Week 2)

#### 🔴 Step 4.1: Install Security Dependencies

```bash
cd /home/biomate/frontend
npm install helmet cors csrf-sync
npm audit fix
```

#### 🔴 Step 4.2: Update Server Configuration

The security configuration has already been created in:
- `/home/biomate/frontend/server/security-config.ts`
- `/home/biomate/frontend/server/encryption.ts`
- `/home/biomate/frontend/server/phi-classification.ts`

Ensure these are imported in `/home/biomate/frontend/server/index.ts` (already done).

#### 🔴 Step 4.3: Enable Security Features

Update `/home/biomate/frontend/.env.production`:

```bash
# Enable production security
NODE_ENV=production
ENABLE_HSTS=true
ENABLE_CSP=true
ENABLE_CSRF=true
CORS_ORIGINS=https://biomate.ai,https://www.biomate.ai
```

#### Step 4.4: Test Security Headers

```bash
# Test security headers
curl -I https://biomate.ai

# Should see:
# Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
# X-Frame-Options: DENY
# X-Content-Type-Options: nosniff
# Content-Security-Policy: ...
```

---

### Phase 5: Monitoring and Logging (Week 3)

#### 🔴 Step 5.1: Configure CloudWatch Logs

```bash
# Install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
sudo dpkg -i amazon-cloudwatch-agent.deb

# Configure agent
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-config-wizard
```

Create `/opt/aws/amazon-cloudwatch-agent/etc/config.json`:

```json
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/biomate/access.log",
            "log_group_name": "/biomate/production/access",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 2555
          },
          {
            "file_path": "/var/log/biomate/security.log",
            "log_group_name": "/biomate/production/security",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 2555
          },
          {
            "file_path": "/var/log/biomate/audit.log",
            "log_group_name": "/biomate/production/audit",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 2555
          }
        ]
      }
    }
  }
}
```

#### 🔴 Step 5.2: Set Up Security Monitoring

```bash
# Create CloudWatch alarms
aws cloudwatch put-metric-alarm \
  --alarm-name biomate-failed-logins \
  --alarm-description "Alert on multiple failed login attempts" \
  --metric-name FailedLoginAttempts \
  --namespace BioMate \
  --statistic Sum \
  --period 300 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --alarm-actions arn:aws:sns:us-west-2:123456789:security-alerts
```

---

### Phase 6: Backup and Disaster Recovery (Week 3)

#### 🔴 Step 6.1: Configure Automated Backups

```bash
# Copy backup script
sudo cp /home/biomate/scripts/backup.sh /usr/local/bin/biomate-backup
sudo chmod +x /usr/local/bin/biomate-backup

# Add to crontab
sudo crontab -e
# Add: 0 2 * * * /usr/local/bin/biomate-backup
```

#### 🔴 Step 6.2: Create S3 Backup Bucket

```bash
# Create backup bucket with encryption
aws s3api create-bucket \
  --bucket biomate-backups \
  --region us-west-2 \
  --create-bucket-configuration LocationConstraint=us-west-2

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket biomate-backups \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket biomate-backups \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Enable lifecycle policy
aws s3api put-bucket-lifecycle-configuration \
  --bucket biomate-backups \
  --lifecycle-configuration file://backup-lifecycle.json
```

`backup-lifecycle.json`:
```json
{
  "Rules": [
    {
      "Id": "TransitionToGlacier",
      "Status": "Enabled",
      "Transitions": [
        {
          "Days": 90,
          "StorageClass": "GLACIER"
        }
      ],
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 90
      }
    }
  ]
}
```

#### 🔴 Step 6.3: Test Backup and Restore

```bash
# Run manual backup
/usr/local/bin/biomate-backup

# Test restore (on test instance)
/usr/local/bin/biomate-restore --date 2025-11-11 --verify
```

---

### Phase 7: Compliance Documentation (Week 4)

#### 🔴 Step 7.1: Complete BAAs

Business Associate Agreements required with:
- [ ] AWS (cloud infrastructure)
- [ ] Anthropic (Claude API)
- [ ] OpenAI (if using)
- [ ] SendGrid (email service)
- [ ] Stripe (payment processing)
- [ ] Monitoring services (Sentry, Datadog, etc.)

Template location: `/home/biomate/legal/BAA_TEMPLATE.md`

#### 🔴 Step 7.2: Create Security Policies

Required documents:
- [x] Security Compliance Audit Report
- [x] Incident Response Plan
- [x] Backup and Disaster Recovery Plan
- [ ] Access Control Policy
- [ ] Acceptable Use Policy
- [ ] Data Retention Policy
- [ ] Employee Training Records

#### 🔴 Step 7.3: Conduct Risk Assessment

Complete HIPAA Risk Assessment:
```bash
# Use provided template
cp /home/biomate/compliance/HIPAA_RISK_ASSESSMENT_TEMPLATE.xlsx \
   /home/biomate/compliance/HIPAA_RISK_ASSESSMENT_2025.xlsx
```

---

## Post-Deployment Validation

### Security Testing Checklist

#### Automated Security Scan

```bash
# Run OWASP ZAP scan
docker run -t owasp/zap2docker-stable zap-baseline.py \
  -t https://biomate.ai \
  -r zap_report.html

# Run npm audit
cd /home/biomate/frontend && npm audit

# Run Snyk scan
npm install -g snyk
snyk test
```

#### Manual Testing

- [ ] HTTPS redirection works
- [ ] Security headers present
- [ ] CORS properly configured
- [ ] CSRF token required for POST requests
- [ ] Session timeout at 15 minutes
- [ ] Audit logging captures events
- [ ] Encrypted data at rest
- [ ] Backup restoration successful
- [ ] Incident response tested

---

## Monitoring Dashboards

### CloudWatch Dashboard

Create monitoring dashboard:

```bash
aws cloudwatch put-dashboard \
  --dashboard-name BioMate-Security \
  --dashboard-body file://security-dashboard.json
```

**Metrics to Monitor:**
- Failed login attempts
- 401/403 errors
- Database connection errors
- Rate limit violations
- SSL/TLS handshake failures
- Backup job success/failure
- Audit log volume

---

## Security Maintenance Schedule

### Daily
- [ ] Review security logs
- [ ] Check backup status
- [ ] Monitor failed login attempts

### Weekly
- [ ] Test backup restoration
- [ ] Review access logs
- [ ] Update dependency security patches

### Monthly
- [ ] Rotate API keys
- [ ] Review user permissions
- [ ] Security scan

### Quarterly
- [ ] Disaster recovery drill
- [ ] Penetration test
- [ ] Compliance audit
- [ ] Update documentation

### Annually
- [ ] Full SOC 2 audit
- [ ] HIPAA risk assessment
- [ ] Incident response drill
- [ ] Security training for all staff

---

## Emergency Contacts

### Security Incidents
- **Security Team:** security@biomate.ai
- **On-Call:** +1-XXX-XXX-XXXX
- **PagerDuty:** https://biomate.pagerduty.com

### Vendor Support
- **AWS Support:** 1-800-XXX-XXXX
- **Anthropic:** support@anthropic.com
- **Security Consultant:** XXXX

---

## Helpful Commands Reference

```bash
# Check SSL certificate expiry
openssl s3_client -connect biomate.ai:443 -servername biomate.ai | openssl x509 -noout -dates

# View audit logs
tail -f /var/log/biomate/audit.log | jq '.'

# Test database backup
pg_dump --version && pg_restore --version

# Check encryption status
aws rds describe-db-instances --db-instance-identifier biomate-prod \
  --query 'DBInstances[0].StorageEncrypted'

# Monitor failed logins
grep "LOGIN_FAILURE" /var/log/biomate/audit.log | wc -l

# Test disaster recovery
aws s3 ls s3://biomate-backups/daily/ | tail -5
```

---

## Next Steps

1. **Complete all 🔴 critical steps**
2. **Schedule SOC 2 readiness assessment**
3. **Engage penetration testing firm**
4. **Schedule security training for team**
5. **Create runbook for common security incidents**
6. **Set up 24/7 on-call rotation**

---

**Document Owner:** Security Team
**Last Updated:** 2025-11-11
**Next Review:** 2026-02-11
