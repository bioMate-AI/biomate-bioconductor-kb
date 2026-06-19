# B.4 — Bucket Policy Lockdown for `s3://biomate-nextflow-work` (Ops handoff)

**Date:** 2026-06-19
**Task:** #70
**For:** ops / AWS-admin engineer
**Deploys with:** commit `7a605a4089` (B.1+B.2+B.3 — counted output endpoint shipped)
**Per user direction:** **atomic deploy** — no deprecation window (assumes no current `aws s3 cp` users on the bucket).

## Why

`s3://biomate-nextflow-work/*` currently allows any IAM principal with `s3:GetObject` to read. Power users could `aws s3 cp` outputs directly, bypassing BioMate's audit log + counted endpoint. With commit `7a605a4089` shipped, the counted endpoint `/api/runs/:id/output/:filename` is the canonical access path. Time to lock the back door.

## What changes

Add a `Deny` statement to the bucket policy that revokes `s3:GetObject` for any principal except BioMate's service IAM role.

### Bucket policy JSON to apply

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowBioMateServiceReadOnly",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::399683337364:role/biomate-service-role"
      },
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::biomate-nextflow-work",
        "arn:aws:s3:::biomate-nextflow-work/*"
      ]
    },
    {
      "Sid": "AllowBioMateServiceWrite",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::399683337364:role/biomate-service-role"
      },
      "Action": [
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:AbortMultipartUpload"
      ],
      "Resource": "arn:aws:s3:::biomate-nextflow-work/*"
    },
    {
      "Sid": "AllowNextflowBatchWrite",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::399683337364:role/biomate-nextflow-batch-role"
      },
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:DeleteObject",
        "s3:AbortMultipartUpload"
      ],
      "Resource": [
        "arn:aws:s3:::biomate-nextflow-work",
        "arn:aws:s3:::biomate-nextflow-work/*"
      ]
    },
    {
      "Sid": "DenyAllOtherPrincipals",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::biomate-nextflow-work",
        "arn:aws:s3:::biomate-nextflow-work/*"
      ],
      "Condition": {
        "StringNotEquals": {
          "aws:PrincipalArn": [
            "arn:aws:iam::399683337364:role/biomate-service-role",
            "arn:aws:iam::399683337364:role/biomate-nextflow-batch-role"
          ]
        }
      }
    }
  ]
}
```

**Two allowed principals (verify the role names match production IAM):**
- `biomate-service-role` — used by Node + Galaxy for presigned URL generation, list, and inline preview reads
- `biomate-nextflow-batch-role` — used by AWS Batch workers writing pipeline outputs

The `DenyAllOtherPrincipals` statement is the lockdown. Even root-account users get denied unless explicitly listed in the allow-list above.

## Pre-deploy verification

Before applying, confirm the role names + ARNs are correct:

```bash
# What roles actually access this bucket right now?
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=biomate-nextflow-work \
  --max-results 50 \
  --region us-east-1 \
  | jq -r '.Events[] | .Username + " " + .EventName' | sort -u | head -20

# What's the current bucket policy?
aws s3api get-bucket-policy --bucket biomate-nextflow-work --output text | jq .
```

If CloudTrail surfaces principals other than `biomate-service-role` and `biomate-nextflow-batch-role` in the last 30 days, **stop and investigate before applying** — that's evidence of an undocumented dependency.

## Apply

```bash
# Save current policy as rollback
aws s3api get-bucket-policy --bucket biomate-nextflow-work --output text \
  | jq . > /tmp/biomate-nextflow-work.policy.backup.$(date +%s).json

# Apply new policy
aws s3api put-bucket-policy --bucket biomate-nextflow-work \
  --policy file:///tmp/biomate-nextflow-work.policy.new.json
```

## Post-deploy verification

```bash
# 1. BioMate's own service role can still read (uses MFA token if assume-role)
aws s3 ls s3://biomate-nextflow-work/ --profile biomate-service-role | head

# 2. A different IAM user is now denied
aws s3 ls s3://biomate-nextflow-work/ --profile some-other-user
# Expected: AccessDenied

# 3. End-to-end functional check — dispatch a small workflow + download output via endpoint
TOKEN=$(curl -sS -X POST https://dev-public.biomate.ai/api/auth/login \
  -H "x-e2e-test-token: $E2E_TEST_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"email":"lifeifei163361@163.com","password":"'$E2E_FIXTURE_PASSWORD'"}' \
  | jq -r .token)

# Dispatch ANY small workflow that produces an output; then:
curl -i -X GET https://dev-public.biomate.ai/api/runs/<run_id>/output/<filename> \
  -H "Cookie: biomate_token=$TOKEN"
# Expected: HTTP/1.1 302 Found  → Location: https://biomate-nextflow-work.s3.us-east-1.amazonaws.com/...
```

## Audit-log verification

After several test downloads, verify the audit-log captured them:

```sql
SELECT accessed_at, user_email, run_id, filename, http_status, file_size_bytes
FROM output_access_log
ORDER BY accessed_at DESC
LIMIT 10;
```

Each download via the endpoint should appear with `http_status = 302` and the filename/sizing matching.

## Rollback

If anything breaks:

```bash
aws s3api put-bucket-policy --bucket biomate-nextflow-work \
  --policy file:///tmp/biomate-nextflow-work.policy.backup.<timestamp>.json
```

Rollback restores the pre-lockdown state (which still has the counted endpoint working in parallel — the endpoint never depended on the policy being closed).

## Notes for ops

1. **The migration `0017_output_access_log.sql` must be applied to production PostgreSQL BEFORE the bucket policy change**, or audit-log writes will fail silently and downloads will still 302 (but with no audit trail). Run order: PG migration → endpoint deploy → bucket policy change.

2. **Per-project layout (Phase C.3)**: when Phase C lands, outputs may be written under `s3://biomate-nextflow-work/projects/<project_id>/runs/<run_id>/...`. This bucket policy applies recursively to all keys including that prefix — no separate policy needed.

3. **Lifecycle policy is NOT modified by this change.** If outputs need automatic expiration (e.g., 90-day default retention), that's a separate lifecycle-policy task — recommend opening a separate ticket.

4. **CloudWatch metric:** consider adding an alarm on `S3 4xx error rate > 5/min` on this bucket — would catch any forgotten client trying to use the back door.

## Acceptance criteria

- [ ] Policy applied via `put-bucket-policy`
- [ ] Pre-lockdown policy saved to `/tmp/biomate-nextflow-work.policy.backup.<ts>.json` (and copied to a durable location)
- [ ] BioMate-service-role read test: passes
- [ ] Foreign-IAM-user read test: returns `AccessDenied`
- [ ] End-to-end download via counted endpoint: returns 302 with valid presigned URL
- [ ] `output_access_log` table shows row for the test download
- [ ] CloudWatch alarm configured (optional)

## Background reading

- `docs/20260619_OUTPUT_LOCKDOWN_PHASE_B_C_SPEC.md` — full Phase B+C spec
- `docs/20260619_OUTPUT_AND_PROJECT_MODEL_AUDIT.md` §"Channel 5" — original concern
- `docs/20260619_NEXT_PHASE_OUTPUT_PROJECT_COLLAB_PLAN.md` — parent plan
- `frontend/server/routes.ts:10318` — the counted endpoint
- `frontend/migrations/0017_output_access_log.sql` — audit-log schema
