# AWS Credentials Setup — Mac / Linux Workstation

**Date:** 2026-05-31
**Audience:** developers setting up a new workstation to access BioMate's AWS account

## What this configures

A `default` AWS CLI profile pointing at the BioMate AWS account
(`399683337364`, `us-west-2`) using the `biomate-admin` IAM user. Enables
`aws s3 …`, `aws batch …`, `aws ec2 …`, etc. against production resources.

This is the same configuration we use on the primary dev workstation —
verified there with `aws sts get-caller-identity`:

```
{
    "UserId": "AIDAV2DX3XSKB34TCMJFT",
    "Account": "399683337364",
    "Arn": "arn:aws:iam::399683337364:user/biomate-admin"
}
```

## Setup steps

### 1. Install AWS CLI v2

**Mac (Homebrew):**
```bash
brew install awscli
```

**Mac (official installer):**
```bash
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o /tmp/awscli.pkg
sudo installer -pkg /tmp/awscli.pkg -target /
```

**Linux (Debian/Ubuntu):**
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscli.zip
unzip /tmp/awscli.zip -d /tmp && sudo /tmp/aws/install
```

Verify: `aws --version` → should print `aws-cli/2.x …`.

### 2. Create `~/.aws/config`

No secrets — safe to commit / copy verbatim:

```ini
[default]
region = us-west-2
output = json
s3 =
    multipart_threshold = 64MB
    multipart_chunksize = 16MB
    max_concurrent_requests = 4
```

The `s3 = …` block tunes upload chunking for the large genomics /
cryo-EM datasets typical in BioMate workflows. Without it, large
uploads occasionally stall.

### 3. Create `~/.aws/credentials`

Get the values from the primary dev workstation (`~/.aws/credentials`
there) — copy via SCP or paste manually. Do **NOT** commit this file.

```ini
[default]
aws_access_key_id = <copy from primary workstation>
aws_secret_access_key = <copy from primary workstation>
```

Three safe ways to transfer:

```bash
# Option A: scp directly (preserves perms)
scp primary-workstation:~/.aws/credentials ~/.aws/credentials

# Option B: cat on primary, paste on Mac (use a password manager
#          buffer, not chat / email / Slack)
cat ~/.aws/credentials  # on primary, then copy-paste into editor on Mac

# Option C: aws configure (interactive)
aws configure
# AWS Access Key ID: <paste>
# AWS Secret Access Key: <paste>
# Default region name: us-west-2
# Default output format: json
```

### 4. Set file permissions

AWS CLI requires owner-only access:

```bash
chmod 700 ~/.aws
chmod 600 ~/.aws/config ~/.aws/credentials
```

### 5. Verify

```bash
aws sts get-caller-identity
```

Expected output:
```
{
    "UserId": "AIDAV2DX3XSKB34TCMJFT",
    "Account": "399683337364",
    "Arn": "arn:aws:iam::399683337364:user/biomate-admin"
}
```

If you see `Account: 399683337364` and `Arn: …/biomate-admin`, you're
connected to the right account with the right identity.

## Security notes

- **Never commit `~/.aws/credentials`.** It's already in standard
  gitignores but double-check before pushing.
- The `biomate-admin` user has **broad permissions** across the
  account. On a daily-driver laptop, prefer a **scoped IAM user**
  (`biomate-dev`, `biomate-ci`, etc.) with just the permissions your
  workflows need. Add as a named profile:
  ```ini
  [biomate-dev]
  region = us-west-2
  output = json
  ```
  and `[biomate-dev]` in `~/.aws/credentials`. Activate per-session:
  `export AWS_PROFILE=biomate-dev`.
- **Rotate keys** every 90 days. AWS Console → IAM → Users →
  `biomate-admin` → Security credentials → Create new access key →
  update `~/.aws/credentials` on every workstation → delete old key.
- If a laptop is lost or compromised, immediately:
  1. AWS Console → IAM → Users → `biomate-admin` → Make access key
     inactive
  2. Create a new key
  3. Update `~/.aws/credentials` on remaining workstations

## What you can do once configured

```bash
# List BioMate's primary S3 buckets
aws s3 ls
# Expected: biomate-nextflow-work, biomate-cryo-data, etc.

# Inspect a recent workflow run's outputs
aws s3 ls s3://biomate-nextflow-work/nextflow/outputs/ --recursive | head

# Send an SSH public key to a dev EC2 instance via instance-connect
aws ec2-instance-connect send-ssh-public-key \
  --instance-id i-06696b0d91f4346e0 \
  --availability-zone us-west-2a \
  --instance-os-user ubuntu \
  --ssh-public-key file://~/.ssh/id_ed25519.pub \
  --region us-west-2

# Check status of a Batch job
aws batch describe-jobs --jobs <job-id> --region us-west-2
```

## Reference: file locations on primary workstation

```
~/.aws/
├── config        # 600 perms; no secrets; region + s3 tuning
└── credentials   # 600 perms; access_key_id + secret_access_key
```
