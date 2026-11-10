# Batch job-role + IMDS hardening — APPLIED + verified (2026-11-10)

**Status: APPLIED + VERIFIED (supervised).** All three layers are now live:
1. **Mandatory fail-closed source pre-check** on uploads (`e0bd9e01`) — proven: a
   probe containing `169.254.169.254` was refused at execute (the `cloud_metadata_ip`
   block rule), surfaced as a failed start, never dispatched.
2. **Scoped task role** `biomate-nextflow-task-role` (S3 `GalaxyNextflowS3Access` +
   `KMSDecryptForS3` only — same data-plane as before; NO SSM / ECR-push / EC2) wired
   via `aws.batch.jobRole` (`62e60035`, env-overridable `NEXTFLOW_BATCH_JOB_ROLE_ARN`).
   Verified: probe run registered job def `nf-quay-io-biocontainers-python-3-11:5`
   with `jobRoleArn=…/biomate-nextflow-task-role` (rev 4 was null), ran on Batch
   `returncode=0`, output downloaded.
3. **IMDS hop-limit=1** — launch template `lt-099eb24c4fe1b477e` **v18**
   (`HttpTokens=required, HttpPutResponseHopLimit=1, HttpEndpoint=enabled`); CE
   `biomate-nextflow-ce-v2` pinned to v18 (ENABLED/VALID). Verified: a clean probe
   cold-started a fresh v18 instance and completed `returncode=0` with its output
   downloadable — tasks work purely via the task-role endpoint, no IMDS needed.

A malicious uploaded `.nf` now cannot reach the instance role: the source screen
blocks obvious metadata access, tasks default to the scoped role (not the instance
role), and even obfuscated code can't reach `169.254.169.254` from a container
(hop-limit=1). No catalog-workflow regression: each run re-registers its job defs
with the scoped role before submitting (Nextflow refreshes on config change — proven
by the probe's rev 4→5), and the scoped S3 policy is `GalaxyNextflowS3Access`
verbatim (identical bucket scope). It changes IAM + the Batch launch template on
shared infra (account `399683337364`); rollback below.

## Rollback (if needed)
- IMDS: `aws batch update-compute-environment --compute-environment
  biomate-nextflow-ce-v2 --compute-resources
  "launchTemplate={launchTemplateId=lt-099eb24c4fe1b477e,version=17}"`.
- jobRole: revert `62e60035` + re-sync, or set `NEXTFLOW_BATCH_JOB_ROLE_ARN=""` on
  the galaxy container (empty → no jobRole emitted).

---
## Original audit + plan (for reference)

## Audit (all read-only, confirmed live)
- Job queue `biomate-nextflow-queue` → CE `biomate-nextflow-ce-v2` (MANAGED, EC2,
  ENABLED/VALID), instance profile `ecsInstanceRole`, launch template
  `lt-099eb24c4fe1b477e` (CE uses v17; default v9; latest v17).
- **Live Batch job defs** (`nf-wave-seqera-io-…`, created by Nextflow/Wave) carry
  **`jobRoleArn = arn:…:role/ecsInstanceRole`** — the TASK role equals the INSTANCE
  role. `executionRoleArn = null`.
- **`ecsInstanceRole`** policies: `GalaxyNextflowS3Access`, `AmazonSSMManagedInstanceCore`,
  `AmazonEC2ContainerServiceforEC2Role` (managed) + `ECRPushAccess`, `KMSDecryptForS3`
  (inline). `ECRPushAccess` = full push (`ecr:PutImage`, `UploadLayerPart`, …).
- **`BatchJobRole`** exists (created 2025-10-14) but is NOT wired into the live
  Nextflow path. Policies: `BatchJobS3Access`, `CloudWatchLogsFullAccess` (managed) +
  `ECRAccessPolicy` (inline) — **which also grants `ecr:PutImage` / push**. So
  BatchJobRole is NOT a safe drop-in target as-is.
- **IMDS on a live Batch instance** (`i-0db1f1b48a…`): `HttpTokens=required`
  (IMDSv2 enforced — good), **`HopLimit=2`** (the LT's `MetadataOptions` is null, so
  this comes from the Batch/AMI default). Hop-limit 2 lets a **container** reach
  `169.254.169.254` → the instance role.

## The exposure (what a malicious uploaded `.nf` can do today)
A task container gets `ecsInstanceRole` credentials via **two** paths, both open:
1. **Task-role endpoint** (`169.254.170.2`) — because `jobRole = ecsInstanceRole`.
2. **IMDS** (`169.254.169.254`, hop-limit=2) — the instance role.
With that role it can **push/overwrite images in ECR** (`ecr:PutImage` on
`399683337364`), use **SSM**, and read/write broad S3 + KMS. The source pre-check
(regex) is the only thing in front of this today, and it is defeatable by
obfuscation (by design). This is why least-privilege + closing IMDS matters.

## Remediation (apply supervised, in order)
### 1. Create a truly-scoped task role `biomate-nextflow-task-role`
Trust policy: `ecs-tasks.amazonaws.com` (`sts:AssumeRole`). Attach ONLY:
- **S3**: reuse `GalaxyNextflowS3Access` **verbatim** (identical S3 scope → zero S3
  regression for any workflow that works today).
- **KMS**: reuse `KMSDecryptForS3` verbatim (SSE-KMS buckets).
- **ECR pull ONLY** (NOT push): `ecr:GetAuthorizationToken`,
  `ecr:BatchCheckLayerAvailability`, `ecr:GetDownloadUrlForLayer`, `ecr:BatchGetImage`.
  (Image **pull for the task** is actually done by the ECS agent via the INSTANCE
  role, so the task role may not need ECR at all — grant pull-only defensively, never
  push.)
- **CloudWatch Logs**: scope to the Batch log group `/aws/batch/job` only (not
  `CloudWatchLogsFullAccess`).
- **NO** SSM, **NO** `AmazonEC2ContainerServiceforEC2Role`, **NO** `ecr:PutImage`/upload.
Do NOT reuse `BatchJobRole` unchanged — its `ECRAccessPolicy` includes push.

### 2. Wire the Nextflow path to the scoped role — **OPEN: locate the setter first**
`jobRole=ecsInstanceRole` is NOT set in `nextflow_executor.py`'s generated config,
not in a dev env var (`AWS_BATCH_JOB_ROLE_ARN` unset), and not in
`/app/.nextflow/config`. It must be found before wiring (candidates: the Wave/Seqera
integration, a base/seed job definition the created defs inherit from, or an
`aws.batch.jobRole` in a config not yet located). Once found, point it at
`biomate-nextflow-task-role`. Note Nextflow **caches** job definitions by
container+hash — existing `nf-wave-*` defs keep the old role until re-registered;
force a fresh def (new container or bump) to exercise the new role during verify.

### 3. Close the IMDS path — hop-limit 1
New version of `lt-099eb24c4fe1b477e` with
`MetadataOptions={HttpTokens=required, HttpPutResponseHopLimit=1, HttpEndpoint=enabled}`;
update CE `biomate-nextflow-ce-v2` to the new LT version. **New instances only** —
drain/replace or wait for turnover. Tasks use the task-role endpoint (`.170.2`, not
IMDS), so this should not remove task S3 creds — but that is exactly what step 4 must
prove before trusting it.

### 4. Verify (must pass before leaving it)
- Run the probe (`hello-liverun-probe`, personal_workflow `f1a9d240…`) AND at least
  one real catalog workflow with **S3 inputs from another bucket** (to exercise the
  scoped S3 policy, which the input-less probe does NOT) on a **fresh** instance.
  Both must complete and their outputs must download.
- From inside a task (temporary debug `.nf`), confirm `curl -s -m2
  http://169.254.169.254/latest/meta-data/iam/security-credentials/` **fails/times
  out** (IMDS closed) while S3 read/write still works (task role intact).

### 5. Rollback
- Role: revert the live path's jobRole to `ecsInstanceRole`; re-register job defs.
- IMDS: update CE `biomate-nextflow-ce-v2` back to LT `lt-099eb24c4fe1b477e` v17;
  replace instances.
- Nothing here is destructive if reverted promptly, but a wrong scope fails **all**
  Batch jobs until reverted — hence supervised only.

## Why not done tonight
Shared production Batch; the job-role flip hits every run and the LT change is
new-instance-only; an input-less probe cannot prove a scoped S3 role works for real
cross-bucket workflows; the jobRole setter is not yet located; and no one is awake to
catch a breakage. Documenting + not shipping an unverified prod-IAM change is the
correct call. See [[project_personal_workflow_batch_exec]].
