# S3 Cross-Region Replication (灾备) — Production Data & Backups

**Date:** 2026-08-07
**Operator:** galaxy-dev (IAM user, account 399683337364)
**Purpose:** Disaster-recovery cross-region replication (CRR) for the two production S3 buckets.

## Scope

| Source (us-east-1) | Replica (us-west-2) |
|---|---|
| `biomate-production-data-399683337364` | `biomate-production-data-399683337364-dr-usw2` |
| `biomate-production-backups-399683337364` | `biomate-production-backups-399683337364-dr-usw2` |

- **Direction:** us-east-1 → us-west-2 (Oregon) — chosen for geographic isolation from the primary region; compute/ElastiCache already run in us-west-2.
- **Data at setup:** data 0.41 GB / 612 objs, backups 7.99 GB / 71 objs (~8.4 GB total).
- Both source buckets already had **versioning enabled** (CRR prerequisite) and **SSE-KMS** default encryption (CMK `58874a28-…`, single-region).

## Resources created

1. **Destination buckets** (us-west-2): versioning enabled, public access fully blocked, default SSE-KMS using the **AWS-managed `aws/s3` key** in us-west-2 (`…/64636f41-…`) — free, avoids a $1/mo customer CMK. `BucketKeyEnabled=true`.
2. **IAM replication role** `biomate-s3-crr-dr-role` (trusts `s3.amazonaws.com` + `batchoperations.s3.amazonaws.com`), inline policy `crr-dr-policy`:
   - source read + `s3:InitiateReplication` + `s3:PutInventoryConfiguration` (for batch manifest gen)
   - dest `s3:ReplicateObject/Delete/Tags`
   - `kms:Decrypt` on source CMK (via `s3.us-east-1`), `kms:Encrypt/GenerateDataKey` on dest `aws/s3` key (via `s3.us-west-2`)
   - batch completion-report PutObject to `crr-batch-reports/`
3. **Replication config** on both source buckets (V2 schema):
   - `SseKmsEncryptedObjects=Enabled`, `ReplicaKmsKeyID` = us-west-2 `aws/s3` key
   - **`DeleteMarkerReplication=Disabled`** — DR safety: accidental/malicious deletes at source do NOT propagate to the replica.
   - **RTC (Replication Time Control) enabled** — 15-minute replication SLA + CloudWatch replication metrics.
4. **S3 Batch Replication backfill** (existing objects — CRR only auto-replicates *new* writes):
   - data job `1cc6ddca-…`: **578/578 tasks, 0 failed, Complete**
   - backups job `38133464-…`: **71/71 tasks, 0 failed, Complete**

## Verification

| Bucket | Source | Replica |
|---|---|---|
| data | 191 current objs / 371.53 MB | 194 objs / 371.53 MB |
| backups | 71 objs / 8182.17 MB | 71 objs / 8182.17 MB |

Byte totals match exactly. The data replica shows 3 extra "current" objects because those source keys currently have a **delete marker** as their latest version (not shown by `s3 ls`); with delete-marker replication disabled, the replica retains the real objects — intended DR behavior.

## Cost (actual)

- **One-time:** ~$0.7 (cross-region transfer ~$0.17 for 8.4 GB + 2 batch jobs @ $0.25 + KMS/requests).
- **Ongoing:** ~$0.2/mo dest storage + light RTC/transfer/request/metrics on new writes. **$0 KMS CMK** (using free `aws/s3` managed key). Estimated **< $2/mo** at current volume; ~$3–5/mo even at 5–10× growth.

## Vanta alignment

- **Governing test:** `aws-s3-cross-region-replication-enabled` ("S3 backup configured for redundancy across regions (AWS)"), was **OVERDUE**.
- **Pass criteria:** a bucket has ≥1 **Enabled** replication rule to a bucket in a **different region**. The test does **not** require a customer-managed CMK — the free `aws/s3` managed key used here is fully compliant. → **No customer CMK is created.**
- **Not disruptive:** CRR is one-directional async replication (reads source, writes replica); it does not touch the source read/write path.
- **Remaining manual UI steps (no MCP API — must be done in the Vanta console):**
  1. The 2 production buckets already have CRR; they flip to **pass** on Vanta's next AWS integration re-scan (auto ~24h, or trigger a manual re-test).
  2. **Deactivate the 2 replica entities** (`...-dr-usw2`) in the failing test — justification: *"destination replica bucket — CRR not required (avoids replication chain)"* (this is Vanta's own recommended remediation for replica/destination buckets).
- Account has only these 4 S3 buckets in test scope; no other buckets need CRR.

## Notes / follow-ups

- New objects written to either source bucket now replicate automatically within the 15-min RTC SLA.
- Permission gaps hit during setup (documented so a future operator isn't surprised): `galaxy-dev` **cannot** `kms:CreateKey` (hence the `aws/s3` managed-key approach); batch manifest generation required adding `s3:PutInventoryConfiguration` to the role.
- Replication status/metrics visible in CloudWatch (`AWS/S3` replication metrics) and per-bucket S3 console → Management → Replication.
- If a future requirement needs replica objects under a customer CMK, an admin with `kms:CreateKey` must create a us-west-2 CMK and update `ReplicaKmsKeyID` + the role's KMS-encrypt resource.
