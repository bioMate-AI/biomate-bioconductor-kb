# BioMate — Security Remediation Team Brief

**Date:** 2026-04-28
**Prepared by:** Security / Engineering
**Audience:** Engineering team, DevOps
**Status:** 3 open items requiring team action — no automated fix applied

---

## Background

A full SOC2/HIPAA security audit was completed on 2026-04-28. An automated evidence collector (`backend/scripts/compliance/collect_evidence.py`) now runs 14 checks monthly and uploads results to S3. The current score is **10/14 passing**.

The 4 resolved items and 7 previously closed gaps are documented in `docs/20260412_SOC2_HIPAA_AUDIT_FRAMEWORK.md`.

This document covers the **3 remaining open items** that require deliberate team action and cannot be automated without human sign-off. Each section contains full context, exact commands, and a recommended sequence.

---

## Item 1 — Root IAM Access Key Active

### Severity: Critical

### What the problem is

The AWS account (`399683337364`) currently has no IAM admin user. All AWS CLI access — local development, the production EC2 `.env` file, and everything done via automation — runs as the **root account** using key `AKIAV2DX3XSKGYVKVDET` (created 2025-10-08).

Using root access keys is a fundamental AWS security violation:
- Root has unrestricted access to every service and cannot be constrained by IAM policies
- If the key leaks, the entire account — billing, all data, all infrastructure — is compromised with no recovery option
- SOC2 CC6.2 and AWS CIS Benchmark 1.4 both require root keys to be absent

### Current IAM state

| User | Type | Permissions | Key status |
|---|---|---|---|
| *(root)* | Root account | Unrestricted | **Active key** `AKIAV2DX3XSKGYVKVDET` |
| `biomate-admin` | IAM user | `AdministratorAccess` | Active key `AKIAV2DX3XSKLG5H4HQ6` — created 2026-04-28, **not yet in use** — retrieve secret from AWS Console → IAM → Users → biomate-admin → Security credentials |
| `galaxy-dev` | IAM service account | EC2, S3, Batch, IAM, Lambda, etc. | In use by Galaxy workflows |
| `biomate-ses-smtp` | IAM service account | SES only | In use for email |

The `biomate-admin` user and its access key have been created and are ready. The migration has **not** been applied. The root key has **not** been deleted.

### What needs to happen — in this exact order

**Step 1 — Update the production EC2 `.env`**

SSH into `BioMate-Production` (52.42.49.175) and edit `/opt/biomate/.env`. Replace the two lines:

```
AWS_ACCESS_KEY_ID=AKIAV2DX3XSKGYVKVDET
AWS_SECRET_ACCESS_KEY=<current root secret>
```

with the `biomate-admin` credentials. Retrieve the secret key from **AWS Console → IAM → Users → biomate-admin → Security credentials → Access keys**.

Then restart the Node.js frontend process to pick up the new env.

**Step 2 — Verify the production app still works**

Run a quick smoke test — confirm a workflow can be submitted and the billing Lambda can be invoked. The new key has `AdministratorAccess` so all existing permissions are covered.

**Step 3 — Update local `~/.aws/credentials` on the dev machine**

```ini
[default]
aws_access_key_id     = AKIAV2DX3XSKLG5H4HQ6
aws_secret_access_key = <retrieve from AWS Console>
```

Verify: `aws sts get-caller-identity` should return `arn:aws:iam::399683337364:user/biomate-admin`.

**Step 4 — Check for any other places the root key is used**

Search for the key ID `AKIAV2DX3XSKGYVKVDET` in:
- Any other `.env` files on dev/staging instances
- CI/CD environment variables (GitHub Actions secrets, etc.)
- Any hardcoded configs in the codebase: `grep -r "AKIAV2DX3XSKGYVKVDET" .`

Replace each occurrence with the new `biomate-admin` key before proceeding.

**Step 5 — Delete the root key (irreversible)**

Only after Steps 1–4 are confirmed working:

```bash
aws iam delete-access-key --access-key-id AKIAV2DX3XSKGYVKVDET
```

Verify it is gone:

```bash
aws iam list-access-keys
# Expected: empty table (root has no keys)
```

**Step 6 — Confirm evidence check passes**

```bash
cd backend/scripts/compliance
python3 collect_evidence.py --no-alert
# Expected: ✅ root_no_access_keys: Root key1_active=False key2_active=False
```

### Notes

- The `biomate-admin` secret key is shown above. Store it in a password manager immediately. This is the only time it is shown in plaintext.
- If access is lost during migration, root account recovery requires MFA device + email. Ensure root console access (via browser) is confirmed working before deleting the key.
- `galaxy-dev` does **not** have `AdministratorAccess` — do not use it as a replacement for root.

---

## Item 2 — SSH Port 22 Open to 0.0.0.0/0 on 6 Security Groups

### Severity: Medium

### What the problem is

Six security groups allow inbound SSH (TCP port 22) from any IP address on the internet. This means any host in the world can attempt to authenticate against these EC2 instances. While password auth is typically disabled on EC2 (key-based only), open port 22 still exposes the SSH service to:
- Brute-force key scanning
- SSH version fingerprinting
- Zero-day exploitation if an SSH CVE is published before patching

### Affected security groups

| Group ID | Name | Description | Instances using it |
|---|---|---|---|
| sg-0b2188a4d48d989b8 | `biomate-sg` | BioMate application | BioMate-Production (52.42.49.175) — **production** |
| sg-07fd63eb018552f64 | `docker-builder-ssh` | Docker builder SSH | Build instances (ephemeral) |
| sg-0caa6a167076f4ee3 | `galaxy-builder-sg` | Galaxy Docker builder | Build instances (ephemeral) |
| sg-0378233ffeda66987 | `launch-wizard-1` | Misc EC2 | Miscellaneous (PostgreSQL rule already removed) |
| sg-0de9af2d4437a8c90 | `default` | Default VPC | Any instance not assigned a custom SG |
| sg-008657d0f1f22b4ce | `galaxy-slurm-minimal-HeadNodeSecurityGroup` | HPC head node | ParallelCluster head node |

### Recommended fix — two-track approach

**Track A: Production (`biomate-sg`) — high priority**

Option A1 (best): Switch to SSM Session Manager — remove port 22 entirely.
- The SSM agent is likely already installed on Amazon Linux / Ubuntu AMIs
- Access via: `aws ssm start-session --target i-06696b0d91f4346e0`
- No inbound ports needed at all — connection goes outbound from the instance to SSM
- EC2 Instance Connect also works over HTTPS with no port 22 required

Command to remove port 22 from `biomate-sg`:
```bash
aws ec2 revoke-security-group-ingress \
  --region us-west-2 \
  --group-id sg-0b2188a4d48d989b8 \
  --protocol tcp --port 22 --cidr 0.0.0.0/0
```

Option A2 (acceptable): Restrict to office/VPN CIDR only. Replace `0.0.0.0/0` with your static IP:
```bash
# Remove open rule
aws ec2 revoke-security-group-ingress \
  --region us-west-2 \
  --group-id sg-0b2188a4d48d989b8 \
  --protocol tcp --port 22 --cidr 0.0.0.0/0

# Add restricted rule (replace x.x.x.x/32 with your office/VPN IP)
aws ec2 authorize-security-group-ingress \
  --region us-west-2 \
  --group-id sg-0b2188a4d48d989b8 \
  --protocol tcp --port 22 --cidr x.x.x.x/32
```

**Track B: Builder and HPC instances — lower priority, team decision**

The builder instances (`docker-builder-ssh`, `galaxy-builder-sg`) are described as temporary. If they are truly ephemeral and terminated when not in use, the risk is lower. The team should decide:

- If these groups are used on running instances: apply Option A1 or A2
- If they are only attached to short-lived build instances that are terminated within hours: document this as accepted risk with a review date

The HPC head node (`galaxy-slurm-minimal-HeadNodeSecurityGroup`) is managed by AWS ParallelCluster and may be recreated on next cluster launch. If the cluster is not currently active, no action is needed. If active, the same options apply.

**The `default` security group:** Best practice is to ensure no instances rely on the default security group at all. Check if any running instances use it:
```bash
aws ec2 describe-instances --region us-west-2 \
  --filters "Name=instance.group-id,Values=sg-0de9af2d4437a8c90" \
  --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0]]' \
  --output table
```

### Verification

After applying fixes, confirm the evidence check passes:
```bash
python3 backend/scripts/compliance/collect_evidence.py --no-alert
# Expected: ✅ sg_no_public_dangerous_ports
```

---

## Item 3 — Lambda API Keys in Plaintext Environment Variables

### Severity: Low (values now in Secrets Manager — this is cleanup)

### What the problem is

Both billing Lambda functions store API keys as plaintext Lambda environment variables. Anyone with `lambda:GetFunctionConfiguration` IAM permission — including any IAM user or role with broad Lambda access — can retrieve these values via the AWS Console or CLI.

### Affected functions

| Function | Region | Plaintext env vars |
|---|---|---|
| `biomate-s3-billing` | us-east-1 | `BILLING_API_KEY` |
| `biomate-batch-billing` | us-west-2 | `BILLING_API_KEY`, `LAGO_API_KEY` |

Both functions share the execution role: `arn:aws:iam::399683337364:role/biomate-lambda-billing-role`

### What is already done

Both secrets have been stored in AWS Secrets Manager (us-west-2):

| Secret name | ARN |
|---|---|
| `biomate/billing/api-key` | `arn:aws:secretsmanager:us-west-2:399683337364:secret:biomate/billing/api-key-1kQ9NZ` |
| `biomate/lago/api-key` | `arn:aws:secretsmanager:us-west-2:399683337364:secret:biomate/lago/api-key-X2c9iL` |

### What still needs to happen

**Step 1 — Add Secrets Manager read permission to the Lambda execution role**

```bash
# Create the policy document
cat > /tmp/sm-lambda-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadBillingSecrets",
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": [
        "arn:aws:secretsmanager:us-west-2:399683337364:secret:biomate/billing/api-key-*",
        "arn:aws:secretsmanager:us-west-2:399683337364:secret:biomate/lago/api-key-*"
      ]
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name biomate-lambda-billing-role \
  --policy-name BillingSecretsReadPolicy \
  --policy-document file:///tmp/sm-lambda-policy.json
```

**Step 2 — Update the Lambda function code**

At the top of each Lambda handler, replace env var reads with Secrets Manager calls. The lookup is cached for the Lambda instance lifetime (warm invocations reuse the fetched value):

```python
import boto3, json, os, functools

@functools.lru_cache(maxsize=None)
def _get_secret(name: str) -> str:
    sm = boto3.client("secretsmanager", region_name="us-west-2")
    return sm.get_secret_value(SecretId=name)["SecretString"]

# Replace:
#   BILLING_API_KEY = os.environ["BILLING_API_KEY"]
#   LAGO_API_KEY    = os.environ["LAGO_API_KEY"]
# With:
BILLING_API_KEY = _get_secret("biomate/billing/api-key")
LAGO_API_KEY    = _get_secret("biomate/lago/api-key")
```

`BILLING_API_URL` and `LAGO_API_URL` are not secrets — they are URLs. These can stay in env vars.

**Step 3 — Deploy and test both Lambdas**

```bash
# Verify biomate-s3-billing can fetch the secret (us-east-1)
aws lambda invoke --region us-east-1 \
  --function-name biomate-s3-billing \
  --payload '{"test": true}' /tmp/response.json && cat /tmp/response.json

# Verify biomate-batch-billing (us-west-2)
aws lambda invoke --region us-west-2 \
  --function-name biomate-batch-billing \
  --payload '{"test": true}' /tmp/response.json && cat /tmp/response.json
```

**Step 4 — Remove the secrets from Lambda environment variables**

Only after Step 3 confirms both functions work:

```bash
# biomate-s3-billing (us-east-1) — keep BILLING_API_URL, remove BILLING_API_KEY
aws lambda update-function-configuration --region us-east-1 \
  --function-name biomate-s3-billing \
  --environment "Variables={BILLING_API_URL=http://35.89.57.94:8081}"

# biomate-batch-billing (us-west-2) — keep URLs, remove keys
aws lambda update-function-configuration --region us-west-2 \
  --function-name biomate-batch-billing \
  --environment "Variables={
    BILLING_API_URL=http://172.31.8.116:8081,
    LAGO_API_URL=http://172.31.18.185:3000,
    REDIS_URL=rediss://master.biomate-redis-enc.xzhevl.usw2.cache.amazonaws.com:6379
  }"
```

**Step 5 — Verify the evidence check passes**

```bash
python3 backend/scripts/compliance/collect_evidence.py --no-alert
# Expected: ✅ lambda_no_plaintext_secrets
```

### Note on cold start latency

The `GetSecretValue` call adds ~50ms on cold start only. Warm invocations use the cached value at zero cost. This is negligible for billing Lambdas which are not latency-sensitive.

---

## Summary — Who Does What

| Item | Owner | Estimated time | Blocker |
|---|---|---|---|
| **Root key migration** | DevOps / whoever holds the production `.env` | 30 min | Must do Steps 1–4 before Step 5 |
| **Port 22 on `biomate-sg`** | DevOps | 15 min | Confirm SSM agent is running on production first |
| **Port 22 on builder SGs** | Engineering | 15 min | Team decision on Option A1 vs accept risk |
| **Lambda secrets** | Engineering | 2 hours | Requires Lambda code changes + deploy |

After all three are done, re-run the evidence collector. Expected final score: **13/14** (the remaining N/A is PostgreSQL backup, which is an architecture note not a control failure).

```bash
cd /home/yzhang/biomate/backend/scripts/compliance
python3 collect_evidence.py
```

Evidence is automatically uploaded to:
`s3://biomate-compliance-evidence-399683337364/YYYY-MM/`

---

*Questions: contact Engineering / Security*
*Evidence bucket: `s3://biomate-compliance-evidence-399683337364/`*
*Audit framework: `docs/20260412_SOC2_HIPAA_AUDIT_FRAMEWORK.md`*
