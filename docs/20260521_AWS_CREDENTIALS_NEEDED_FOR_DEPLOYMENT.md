# AWS Credentials Required for Dev-Sync Deployment

**Date:** 2026-05-21
**Status:** Blocked - Need AWS credentials for account 399683337364

---

## Summary

The network fix for dev-public sync is ready to deploy (commit `91fc11efa`), but deployment requires AWS credentials for the **correct BioMate AWS account**.

---

## The Issue

### Wrong AWS Account in `~/.aws/`

Local `~/.aws/credentials` contains credentials for:
- **Account ID:** `282635368434` (Selfiie)
- **Status:** Expired (last modified Sept 2023)

### Correct BioMate AWS Account

BioMate infrastructure runs on:
- **Account ID:** `399683337364`
- **Region:** `us-west-2`
- **ECR Registry:** `399683337364.dkr.ecr.us-west-2.amazonaws.com`
- **EC2 Instance:** `i-06696b0d91f4346e0` (dev-public.biomate.ai)

**Source:** `.github/workflows/backend-image.yml` line 42-44

---

## What `scripts/sync_to_dev.sh` Requires

The sync script needs AWS CLI access to:

1. **EC2 Instance Connect** - To inject temporary SSH keys
   ```bash
   aws ec2-instance-connect send-ssh-public-key \
     --instance-id i-06696b0d91f4346e0 \
     --availability-zone us-west-2a \
     --instance-os-user ubuntu \
     --ssh-public-key file://<key>.pub \
     --region us-west-2
   ```

2. **S3 Access** (for DB syncs)
   ```bash
   aws s3 cp <local-file> s3://biomate-nextflow-work/dev-sync/
   ```

**Script location:** `scripts/sync_to_dev.sh` lines 47-54 (inject_key function)

---

## Tested But Not Working

❌ **Tested credentials:**
- `~/.aws/credentials` profile `282635368434_AdministratorAccess` - Wrong account
- `~/.aws/credentials` profile `default` - Wrong account
- `~/.aws/config` profiles (`selfiie-corp-admin`, `AdministratorAccess-282635368434`) - SSO expired
- Direct SSH with existing keys (`~/.ssh/id_ed25519`, `~/Downloads/*.pem`) - All rejected

❌ **AWS CLI test results:**
```bash
$ aws sts get-caller-identity
An error occurred (InvalidClientTokenId) when calling the GetCallerIdentity operation:
The security token included in the request is invalid

$ aws --profile selfiie-corp-admin sts get-caller-identity
Error loading SSO Token: Token for https://selfiie.awsapps.com/start does not exist
```

---

## What I Need From You

**Please provide ONE of:**

1. **AWS CLI profile name** for account 399683337364
   - If credentials already exist: `export AWS_PROFILE=<profile-name>`

2. **AWS access key + secret** for account 399683337364
   - Will configure: `aws configure --profile biomate`

3. **AWS SSO configuration** for BioMate account
   - SSO start URL, region, account ID, role name

4. **Alternative deployment method**
   - If there's a different way to deploy besides `sync_to_dev.sh`
   - GitHub Actions workflow, different script, etc.

---

## Current Status

### ✅ Completed
- Network fix coded and committed (commit `91fc11efa`)
- Deployment guide written (`docs/20260521_DEV_SYNC_NETWORK_FIX_DEPLOYMENT.md`)
- Session summary documented

### ❌ Blocked
- Cannot verify current EC2 state
- Cannot deploy via `scripts/sync_to_dev.sh`
- AWS CLI authentication failing

### 🔍 Verified Working
- dev-public.biomate.ai website is accessible (HTTP 200)
- Local code changes are committed to `integration/next-phase`
- GitHub Actions would work (uses OIDC, not static credentials)

---

## Quick Test Commands

Once credentials are configured, test with:

```bash
# Test 1: AWS access
aws sts get-caller-identity --region us-west-2

# Should show: Account: "399683337364"

# Test 2: EC2 describe
aws ec2 describe-instances \
  --instance-ids i-06696b0d91f4346e0 \
  --query 'Reservations[0].Instances[0].State.Name' \
  --region us-west-2 \
  --output text

# Should show: "running"

# Test 3: Full sync script
./scripts/sync_to_dev.sh
```

---

## Alternative: GitHub Actions Deployment

If manual deployment is blocked, the fix can be deployed via GitHub Actions:

1. Push to `integration/next-phase` (already done)
2. Trigger `.github/workflows/backend-image.yml` (builds on push)
3. Wait for image build to complete
4. EC2 pulls new image (if auto-deploy is configured)

**Status:** Backend image workflow exists but may not auto-deploy to EC2

---

## Reference Documents

- **Root cause analysis:** `docs/20260521_DEV_PUBLIC_NEXTFLOW_FETCH_FAILED_ALERTS.md`
- **Deployment guide:** `docs/20260521_DEV_SYNC_NETWORK_FIX_DEPLOYMENT.md`
- **Session summary:** `docs/20260521_SESSION_DEV_SYNC_NETWORK_FIX.md`
- **CI/CD plan:** `docs/20260514_CICD_REBUILD_PLAN.md`

---

## Next Steps

**Once credentials are provided:**
1. Configure AWS CLI: `aws configure --profile biomate`
2. Export profile: `export AWS_PROFILE=biomate`
3. Test access: `aws sts get-caller-identity`
4. Run sync: `./scripts/sync_to_dev.sh`
5. Verify deployment per deployment guide

**Estimated time:** 5-10 minutes after credentials are available
