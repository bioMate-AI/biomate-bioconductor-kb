# Batch job-role + IMDS hardening — audit + ready-to-apply plan (2026-11-10)

**Status: AUDITED, NOT APPLIED.** The app-level control (mandatory, fail-closed
source pre-check on uploads — commit `e0bd9e01`) is shipped. The infra hardening
below is defense-in-depth for running arbitrary user `.nf` on shared Batch. It
changes IAM + the Batch launch template on **shared production** infra (account
`399683337364`, used by all environments) and can break **every** workflow run
(catalog + uploaded) if mis-scoped. It was deliberately NOT applied autonomously
overnight (unverifiable against real cross-bucket workflows with no one to catch a
breakage). Apply in a supervised daytime window with the verification + rollback
below.

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
