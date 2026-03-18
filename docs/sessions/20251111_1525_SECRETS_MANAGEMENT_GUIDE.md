# BioMate AI Secrets Management Guide
**Date:** 2025-11-11
**Version:** 1.0
**Compliance:** SOC 2 CC6.1, HIPAA §164.308(a)(4)

---

## Overview

This guide covers the complete lifecycle of secrets management for BioMate AI, including generation, storage, rotation, and access control.

**Security Principles:**
- Secrets are never stored in code or version control
- All secrets use cryptographically secure random generation
- Secrets are encrypted at rest using AWS KMS
- Access to secrets follows principle of least privilege
- Secrets are rotated every 90 days

---

## Table of Contents

1. [Secrets Inventory](#secrets-inventory)
2. [Initial Setup](#initial-setup)
3. [Secret Generation](#secret-generation)
4. [Storing Secrets in AWS](#storing-secrets-in-aws)
5. [Accessing Secrets](#accessing-secrets)
6. [Secret Rotation](#secret-rotation)
7. [Emergency Procedures](#emergency-procedures)
8. [Compliance Requirements](#compliance-requirements)

---

## Secrets Inventory

### Application Secrets

| Secret Name | Purpose | Strength | Rotation Frequency |
|-------------|---------|----------|-------------------|
| JWT_SECRET | JSON Web Token signing | 512 bits | 90 days |
| SESSION_SECRET | Express session encryption | 512 bits | 90 days |
| ENCRYPTION_KEY | AES-256-GCM data encryption | 256 bits | 90 days |
| CSRF_SECRET | CSRF token generation | 256 bits | 90 days |
| COOKIE_SECRET | Signed cookie encryption | 256 bits | 90 days |
| INTERNAL_API_KEY | Internal service authentication | UUID v4 | 90 days |
| WEBHOOK_SECRET | Webhook signature verification | 384 bits | 90 days |

### Infrastructure Secrets

| Secret Name | Purpose | Strength | Rotation Frequency |
|-------------|---------|----------|-------------------|
| DB_PASSWORD | PostgreSQL database password | 192 bits | 90 days |
| REDIS_PASSWORD | Redis cache password | 192 bits | 90 days |
| BACKUP_ENCRYPTION_KEY | Backup file encryption | 256 bits | 90 days |

### Third-Party API Keys

| Secret Name | Purpose | Rotation Frequency |
|-------------|---------|-------------------|
| ANTHROPIC_API_KEY | Claude API access | When rotated by vendor |
| OPENAI_API_KEY | OpenAI API access | When rotated by vendor |

**Total Secrets Managed:** 13

---

## Initial Setup

### Prerequisites

1. **AWS CLI installed and configured:**
   ```bash
   aws --version
   aws sts get-caller-identity
   ```

2. **Required tools:**
   ```bash
   sudo apt install -y jq openssl
   ```

3. **AWS permissions:**
   - `secretsmanager:CreateSecret`
   - `secretsmanager:UpdateSecret`
   - `secretsmanager:GetSecretValue`
   - `kms:Decrypt`
   - `kms:Encrypt`

4. **KMS key (optional but recommended):**
   ```bash
   # Create dedicated KMS key for BioMate secrets
   aws kms create-key \
     --description "BioMate production secrets encryption" \
     --tags TagKey=Application,TagValue=biomate

   # Create alias
   aws kms create-alias \
     --alias-name alias/biomate-secrets \
     --target-key-id <key-id>
   ```

---

## Secret Generation

### Step 1: Generate Secrets

```bash
cd /home/yzhang/biomate/scripts/security
./generate-secrets.sh
```

**What happens:**
1. Generates 10 cryptographically secure secrets
2. Creates JSON file for AWS upload
3. Creates .env file for local use
4. Displays secret strength information
5. Provides next steps

**Output files (in temp directory):**
- `secrets.json` - For AWS Secrets Manager upload
- `.env.production.secrets` - For local use

**Example output:**
```
=========================================
BioMate Production Secrets Generator
=========================================

Generating secure production secrets...

Generating JWT secret...
Generating session secret...
Generating encryption key...
Generating CSRF secret...
Generating database password...
Generating Redis password...
Generating backup encryption key...
Generating internal API key...
Generating webhook secret...
Generating cookie secret...

✓ All secrets generated successfully

=========================================
Secret Strength Information
=========================================

JWT Secret:              88 characters (512 bits)
Session Secret:          88 characters (512 bits)
Encryption Key:          44 characters (256 bits)
CSRF Secret:             44 characters (256 bits)
Database Password:       32 characters (192 bits entropy)
Redis Password:          32 characters (192 bits entropy)
Backup Encryption Key:   44 characters (256 bits)
Internal API Key:        UUID v4 (122 bits entropy)
Webhook Secret:          96 characters (384 bits)
Cookie Secret:           44 characters (256 bits)

✓ All secrets meet NIST SP 800-131A requirements
```

### Step 2: Save or Upload

**Option A: Save locally (for review)**
```
Save secrets to current directory? (yes/no): yes

✓ Secrets saved to:
  - biomate-secrets-20251111_152530.json
  - biomate-secrets-20251111_152530.env

⚠️  CRITICAL: Move these files to a secure location NOW
⚠️  Delete them after uploading to AWS Secrets Manager
```

**Option B: Upload immediately**
```
Upload to AWS Secrets Manager now? (yes/no): yes

Uploading to AWS Secrets Manager...
[Upload process continues...]
```

### Secret Generation Best Practices

1. **Never reuse secrets across environments** (dev, staging, production)
2. **Generate new secrets for each deployment**
3. **Delete local copies immediately after upload**
4. **Verify upload success before deletion**

---

## Storing Secrets in AWS

### Automatic Upload (Recommended)

```bash
./store-secrets-aws.sh biomate-secrets-20251111_152530.json
```

### Manual Upload

```bash
# Set environment variables
export AWS_REGION=us-west-2
export DB_HOST=biomate-prod-db.xxxxx.us-west-2.rds.amazonaws.com
export REDIS_HOST=biomate-prod-redis.xxxxx.cache.amazonaws.com

# Run upload script
./store-secrets-aws.sh biomate-secrets-20251111_152530.json
```

**Upload process:**
```
=========================================
AWS Secrets Manager Upload Script
=========================================

Configuration:
  AWS Region: us-west-2
  Secret Prefix: biomate/prod
  KMS Key: alias/aws/secretsmanager

Uploading secrets to AWS Secrets Manager...

1. Application Secrets
  biomate/prod/app-secrets... created

2. Database Credentials
  biomate/prod/database... created

3. Redis Credentials
  biomate/prod/redis... created

4. Backup Encryption
  biomate/prod/backup... created

✓ All secrets uploaded successfully
```

### AWS Secrets Manager Structure

**Secret: `biomate/prod/app-secrets`**
```json
{
  "jwt_secret": "...",
  "session_secret": "...",
  "encryption_key": "...",
  "csrf_secret": "...",
  "cookie_secret": "...",
  "internal_api_key": "...",
  "webhook_secret": "..."
}
```

**Secret: `biomate/prod/database`**
```json
{
  "host": "biomate-prod-db.xxxxx.rds.amazonaws.com",
  "port": "5432",
  "database": "biomate",
  "username": "biomate_app",
  "password": "...",
  "ssl": true
}
```

**Secret: `biomate/prod/redis`**
```json
{
  "host": "biomate-prod-redis.xxxxx.cache.amazonaws.com",
  "port": "6379",
  "password": "...",
  "tls": true
}
```

**Secret: `biomate/prod/backup`**
```json
{
  "encryption_key": "..."
}
```

### IAM Policy for Secret Access

Add this policy to your EC2 instance IAM role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": [
        "arn:aws:secretsmanager:us-west-2:*:secret:biomate/prod/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt"
      ],
      "Resource": [
        "arn:aws:kms:us-west-2:*:key/*"
      ],
      "Condition": {
        "StringEquals": {
          "kms:ViaService": [
            "secretsmanager.us-west-2.amazonaws.com"
          ]
        }
      }
    }
  ]
}
```

Apply the policy:

```bash
# Get instance role name
INSTANCE_ROLE=$(aws ec2 describe-instances \
  --instance-ids <instance-id> \
  --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
  --output text | awk -F'/' '{print $NF}')

# Create policy
aws iam create-policy \
  --policy-name BioMateSecretsAccess \
  --policy-document file://iam-secrets-policy.json

# Attach to role
aws iam attach-role-policy \
  --role-name $INSTANCE_ROLE \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/BioMateSecretsAccess
```

---

## Accessing Secrets

### Method 1: Load to Environment File (Recommended for Systemd)

```bash
./load-secrets-from-aws.sh /home/biomate/biomate/.env.production
chmod 600 /home/biomate/biomate/.env.production
```

Then reference in systemd service:

```ini
[Service]
EnvironmentFile=/home/biomate/biomate/.env.production
```

### Method 2: Direct AWS SDK Access (Runtime)

**Node.js implementation:**

```typescript
// frontend/server/secrets.ts
import AWS from 'aws-sdk';

const secretsManager = new AWS.SecretsManager({
  region: process.env.AWS_REGION || 'us-west-2'
});

interface SecretCache {
  [key: string]: {
    value: any;
    expiresAt: number;
  };
}

class SecretsManager {
  private cache: SecretCache = {};
  private cacheDuration = 300000; // 5 minutes

  async getSecret(secretName: string): Promise<any> {
    // Check cache
    const cached = this.cache[secretName];
    if (cached && Date.now() < cached.expiresAt) {
      return cached.value;
    }

    // Fetch from AWS
    try {
      const data = await secretsManager.getSecretValue({
        SecretId: secretName
      }).promise();

      const secretValue = JSON.parse(data.SecretString || '{}');

      // Update cache
      this.cache[secretName] = {
        value: secretValue,
        expiresAt: Date.now() + this.cacheDuration
      };

      return secretValue;
    } catch (error) {
      console.error(`Failed to retrieve secret ${secretName}:`, error);
      throw error;
    }
  }

  async loadAllSecrets(): Promise<void> {
    const appSecrets = await this.getSecret('biomate/prod/app-secrets');
    const dbSecrets = await this.getSecret('biomate/prod/database');
    const redisSecrets = await this.getSecret('biomate/prod/redis');
    const backupSecrets = await this.getSecret('biomate/prod/backup');

    // Set environment variables
    process.env.JWT_SECRET = appSecrets.jwt_secret;
    process.env.SESSION_SECRET = appSecrets.session_secret;
    process.env.ENCRYPTION_KEY = appSecrets.encryption_key;
    process.env.CSRF_SECRET = appSecrets.csrf_secret;
    process.env.COOKIE_SECRET = appSecrets.cookie_secret;

    process.env.DB_HOST = dbSecrets.host;
    process.env.DB_PASSWORD = dbSecrets.password;

    process.env.REDIS_HOST = redisSecrets.host;
    process.env.REDIS_PASSWORD = redisSecrets.password;

    process.env.BACKUP_ENCRYPTION_KEY = backupSecrets.encryption_key;
  }

  clearCache(): void {
    this.cache = {};
  }
}

export const secretsManager = new SecretsManager();
```

**Usage in application:**

```typescript
// frontend/server/index.ts
import { secretsManager } from './secrets';

async function startServer() {
  // Load secrets at startup
  await secretsManager.loadAllSecrets();

  // Start Express app
  const app = express();
  // ... rest of setup
}

startServer().catch(console.error);
```

### Method 3: CLI Access (Scripts)

```bash
# Get specific secret
aws secretsmanager get-secret-value \
  --secret-id biomate/prod/app-secrets \
  --query 'SecretString' \
  --output text | jq -r '.jwt_secret'

# Use in script
DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id biomate/prod/database \
  --query 'SecretString' \
  --output text | jq -r '.password')
```

---

## Secret Rotation

### Rotation Schedule

**Frequency:** Every 90 days
**Next Rotation:** 2026-02-09 (90 days from 2025-11-11)

### Rotation Procedure

**Step 1: Generate New Secrets**
```bash
./generate-secrets.sh
```

**Step 2: Upload to AWS (Creates New Versions)**
```bash
./store-secrets-aws.sh biomate-secrets-YYYYMMDD_HHMMSS.json
```

**Step 3: Update Application**
```bash
# Reload environment on all servers
./load-secrets-from-aws.sh /home/biomate/biomate/.env.production

# Restart services
sudo systemctl restart biomate-frontend
sudo systemctl restart biomate-backend
```

**Step 4: Verify**
```bash
# Test application health
curl https://biomate.ai/health

# Test authentication
curl -X POST https://biomate.ai/api/auth/test

# Run security tests
./scripts/security/test-security.sh
```

**Step 5: Clean Up**
```bash
# Shred old secrets file
shred -u biomate-secrets-*.json biomate-secrets-*.env

# Document rotation
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) - Secrets rotated successfully" >> /var/log/biomate/secret-rotation.log
```

### Database Password Rotation (Special Procedure)

Database password rotation requires coordination to avoid downtime:

**Step 1: Create New Password**
```bash
NEW_DB_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)
```

**Step 2: Add New Password to Database**
```sql
-- Connect as admin
psql -h $DB_HOST -U biomateadmin -d postgres

-- Change password for app user
ALTER USER biomate_app WITH PASSWORD 'NEW_PASSWORD_HERE';
```

**Step 3: Update AWS Secrets Manager**
```bash
# Update secret with new password
aws secretsmanager update-secret \
  --secret-id biomate/prod/database \
  --secret-string "$(jq -n \
    --arg host "$DB_HOST" \
    --arg password "$NEW_DB_PASSWORD" \
    '{host: $host, port: "5432", database: "biomate", username: "biomate_app", password: $password, ssl: true}')"
```

**Step 4: Rolling Restart**
```bash
# Reload secrets
./load-secrets-from-aws.sh

# Restart with minimal downtime
sudo systemctl reload biomate-frontend
sleep 5
sudo systemctl reload biomate-backend
```

**Step 5: Verify Connection**
```bash
psql -h $DB_HOST -U biomate_app -d biomate -c "SELECT 1;"
```

### Automated Rotation (Future Enhancement)

AWS Secrets Manager supports automatic rotation using Lambda functions. Implementation steps:

1. Create Lambda function for rotation logic
2. Configure rotation schedule in Secrets Manager
3. Test rotation in non-production environment
4. Enable for production

---

## Emergency Procedures

### Secret Compromise

**If a secret is compromised:**

**IMMEDIATE (< 15 minutes):**
```bash
# 1. Revoke compromised secret
# Generate new secret immediately
./generate-secrets.sh

# 2. Upload to AWS
./store-secrets-aws.sh <new-secrets-file>

# 3. Restart all services
sudo systemctl restart biomate-frontend biomate-backend

# 4. Verify services are healthy
curl https://biomate.ai/health
```

**SHORT TERM (< 1 hour):**
```bash
# 1. Review access logs
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=GetSecretValue \
  --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
  --query 'Events[*].[EventTime,Username,EventName]'

# 2. Check for unauthorized access
sudo tail -f /var/log/biomate/audit.log | grep -i "unauthorized"

# 3. Notify security team
# Send incident report
```

**LONG TERM (< 24 hours):**
```bash
# 1. Complete incident report
# See: Incident Response Plan

# 2. Review and update IAM policies
# Restrict access further if needed

# 3. Conduct post-incident review
# Document lessons learned
```

### AWS Secrets Manager Unavailable

**Fallback procedure:**

1. **Use local backup secrets** (emergency only):
   ```bash
   # Restore from secure backup location
   cp /secure/backup/.env.production /home/biomate/biomate/
   chmod 600 /home/biomate/biomate/.env.production
   sudo systemctl restart biomate-frontend biomate-backend
   ```

2. **Monitor AWS status:**
   ```bash
   # Check AWS Service Health Dashboard
   # https://status.aws.amazon.com/
   ```

3. **Switch to environment variables** (temporary):
   ```bash
   # Set critical secrets as environment variables
   export JWT_SECRET="..."
   # Restart services manually
   ```

---

## Compliance Requirements

### SOC 2 Trust Services Criteria

**CC6.1 - Logical and Physical Access Controls**
- ✅ Secrets stored in encrypted AWS Secrets Manager
- ✅ Access controlled via IAM policies
- ✅ Principle of least privilege enforced
- ✅ All access logged to CloudTrail

**CC6.2 - Confidential Information**
- ✅ Secrets encrypted at rest (AWS KMS)
- ✅ Secrets encrypted in transit (TLS 1.3)
- ✅ Secrets never stored in code/version control

**CC6.7 - Transmission Security**
- ✅ All secret transmission over TLS 1.3
- ✅ AWS API calls use HTTPS only

**CC7.2 - Security Monitoring**
- ✅ CloudTrail logs all secret access
- ✅ Alerts on unauthorized access attempts

### HIPAA Security Rule

**§164.308(a)(4)(ii)(B) - Access Authorization**
- ✅ Access to secrets limited to authorized personnel
- ✅ IAM roles define access permissions
- ✅ MFA required for AWS console access

**§164.308(a)(5)(ii)(D) - Password Management**
- ✅ Secrets use cryptographically secure generation
- ✅ Minimum 192-bit entropy for passwords
- ✅ 90-day rotation schedule

**§164.312(a)(2)(i) - Unique User Identification**
- ✅ Each service has unique credentials
- ✅ No shared secrets across environments

**§164.312(d) - Integrity Controls**
- ✅ AWS Secrets Manager maintains versioning
- ✅ All changes logged to CloudTrail
- ✅ Checksums verify secret integrity

### Evidence Collection for Audits

**Secrets Management Documentation:**
- This guide
- IAM policies granting secret access
- CloudTrail logs of secret access
- Secret rotation logs
- Incident response procedures

**To generate audit evidence:**
```bash
# List all secrets
aws secretsmanager list-secrets --region us-west-2

# Get secret metadata (no values)
aws secretsmanager describe-secret --secret-id biomate/prod/app-secrets

# Export CloudTrail logs (last 90 days)
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=GetSecretValue \
  --start-time $(date -u -d '90 days ago' +%Y-%m-%dT%H:%M:%S) \
  --output json > secrets-access-audit-$(date +%Y%m%d).json

# Generate rotation history
aws secretsmanager list-secret-version-ids \
  --secret-id biomate/prod/app-secrets \
  --query 'Versions[*].[VersionId,CreatedDate]' \
  --output table
```

---

## Appendix A: Secret Strength Requirements

### NIST SP 800-131A Compliance

All secrets meet or exceed NIST requirements:

| Secret Type | NIST Requirement | BioMate Implementation |
|-------------|------------------|------------------------|
| Symmetric Keys | ≥ 112 bits | 256 bits (AES-256) |
| Passwords | ≥ 80 bits entropy | 192 bits entropy |
| HMAC Keys | ≥ 112 bits | 256-512 bits |
| Session Keys | ≥ 112 bits | 512 bits |

### Entropy Calculation

**Example: Database Password**
- Length: 32 characters
- Character set: 64 (A-Z, a-z, 0-9, +, /)
- Entropy: log2(64^32) = 192 bits ✅

**Example: JWT Secret (base64)**
- Length: 88 characters
- Character set: 64
- Entropy: log2(64^88) ≈ 528 bits ✅

---

## Appendix B: Quick Reference

### Common Commands

```bash
# Generate new secrets
./scripts/security/generate-secrets.sh

# Upload to AWS
./scripts/security/store-secrets-aws.sh <secrets-file.json>

# Load from AWS
./scripts/security/load-secrets-from-aws.sh

# View secret (no value)
aws secretsmanager describe-secret --secret-id biomate/prod/app-secrets

# Get secret value
aws secretsmanager get-secret-value --secret-id biomate/prod/app-secrets

# List all secrets
aws secretsmanager list-secrets --filters Key=name,Values=biomate/prod

# Delete local secrets securely
shred -u biomate-secrets-*.json biomate-secrets-*.env
```

### Important Files

- Scripts: `/home/yzhang/biomate/scripts/security/`
- Environment: `/home/biomate/biomate/.env.production`
- Rotation log: `/var/log/biomate/secret-rotation.log`

### Contacts

- **Security Lead:** [Contact]
- **DevOps Lead:** [Contact]
- **On-Call:** [PagerDuty]

---

**Document Owner:** Security Lead
**Last Updated:** 2025-11-11
**Next Review:** 2026-02-09 (90 days)
**Classification:** CONFIDENTIAL

---

**Related Documentation:**
- [Security Setup Guide](20251111_1445_SECURITY_SETUP_GUIDE.md)
- [Incident Response Plan](20251111_1435_INCIDENT_RESPONSE_PLAN.md)
- [Production Deployment Guide](20251111_1515_PRODUCTION_DEPLOYMENT_GUIDE.md)
