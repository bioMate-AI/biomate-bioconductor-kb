# Batch spot migration + cost plan (ready to run, supervised)

**Date:** 2026-10-04
**Context:** owner flagged on-demand EC2 cost ("ec2") + approved moving Batch to spot ("both").
**Why not executed autonomously overnight:** these change the shared Batch compute environment +
the two production queues (`galaxy-cloud-queue`, `biomate-nextflow-queue`) that the product and
every concurrent session use. A misconfig at 2am, unattended, could strand all Batch jobs for hours.
Benefit of doing it now vs. supervised ≈ $10–15; risk ≈ a Batch outage. So: **run these with eyes on
`aws batch describe-compute-environments` + a test job, awake.** All commands validated against the
live CE config (region us-west-2).

Current CE `biomate-nextflow-ce-v2`: `type=EC2`, `minvCpus=4` (keeps ≥1 r5 always warm — the standing
cost), `maxvCpus=48`, BEST_FIT_PROGRESSIVE, no spot. Spot service-linked role
`AWSServiceRoleForEC2Spot` exists. (Batch CE provisioning type is immutable → can't flip in place;
must add a SPOT CE.)

---

## Option A (lowest risk, biggest immediate $ win) — scale the on-demand CE to zero when idle
In-place, reversible, non-disruptive to running jobs. Removes the always-on r5 baseline (~$12/day).
Tradeoff: first job after an idle period pays a ~2–4 min cold start.
```bash
aws batch update-compute-environment --region us-west-2 \
  --compute-environment biomate-nextflow-ce-v2 \
  --compute-resources minvCpus=0
# revert: minvCpus=4
```
**Recommended as step 1 regardless of the spot decision.**

## Option B (spot, reliability tradeoff) — add a SPOT CE as preferred, keep on-demand as fallback
Additive + safe: if spot capacity is unavailable or a spot node is reclaimed, jobs fall back to the
on-demand CE (so it is NOT "all jobs on fragile spot"). SPOT_CAPACITY_OPTIMIZED uses the
service-linked role (no fleet role needed).
```bash
# 1. create the spot CE (mirrors the on-demand networking/role/AMI)
aws batch create-compute-environment --region us-west-2 \
  --compute-environment-name biomate-nextflow-ce-spot --type MANAGED --state ENABLED \
  --service-role arn:aws:iam::399683337364:role/aws-service-role/batch.amazonaws.com/AWSServiceRoleForBatch \
  --compute-resources '{"type":"SPOT","allocationStrategy":"SPOT_CAPACITY_OPTIMIZED","minvCpus":0,"maxvCpus":48,"instanceTypes":["m5.large","m5.xlarge","m5.2xlarge","m5.4xlarge","c5.xlarge","c5.2xlarge","c5.4xlarge","r5.xlarge","r5.2xlarge"],"subnets":["subnet-0254e4c3634b41bfc","subnet-03b277a7a08d388c1","subnet-0b35a6e2c1cf02dc2","subnet-09e4dce46682a6c60"],"securityGroupIds":["sg-0de9af2d4437a8c90"],"instanceRole":"arn:aws:iam::399683337364:instance-profile/ecsInstanceRole","ec2Configuration":[{"imageType":"ECS_AL2023","imageIdOverride":"ami-029a8a79a5e984472"}],"bidPercentage":100}'
# 2. wait until it is VALID/ENABLED:
aws batch describe-compute-environments --compute-environments biomate-nextflow-ce-spot --region us-west-2 --query 'computeEnvironments[0].[status,state]' --output text
# 3. re-point BOTH queues: spot preferred (order 0), on-demand fallback (order 1)
aws batch update-job-queue --region us-west-2 --job-queue biomate-nextflow-queue \
  --compute-environment-order order=0,computeEnvironment=biomate-nextflow-ce-spot order=1,computeEnvironment=biomate-nextflow-ce-v2
aws batch update-job-queue --region us-west-2 --job-queue galaxy-cloud-queue \
  --compute-environment-order order=0,computeEnvironment=biomate-nextflow-ce-spot order=1,computeEnvironment=biomate-nextflow-ce-v2
# 4. submit one cheap test job (e.g. re-run merfish) and confirm it lands on the spot CE + succeeds
# revert: update both queues back to only order=0 biomate-nextflow-ce-v2
```
**Reliability note:** Nextflow workflow tasks are not all idempotent on spot reclaim; Nextflow retries,
but long single-task steps can lose progress. Acceptable for most; validate on the merfish/voyager
runs before trusting long pipelines.

## Option C — g5 GPU training (`i-02979c338c4e31a97`, `unimomo-cyclic-ft`) onto spot
**Not actionable by me:** it is a *concurrent session's* live training; I don't own it, lack its
launch config + checkpoint state, and killing it would destroy in-progress work. The owning session
(or you) should relaunch it on a spot `g5.4xlarge` with S3 checkpointing (the standard research-spot
pattern), after confirming it checkpoints so a reclaim is harmless.

---

## Recommendation
1. Run **Option A now** (safe, reversible, kills the always-on r5 cost).
2. Run **Option B** when you can watch a test job land on spot (cheap, reversible, fallback-protected).
3. Hand **Option C** to the session that launched the g5.

---

## EXECUTION OUTCOME (2026-10-04, owner said "go")

Executed + tested, then **partially reverted on new evidence**:

- **Option A — DONE, kept.** `biomate-nextflow-ce-v2 minvCpus 4→0`. Verified the always-on r5 scaled
  down (both CEs reached 0 instances). The standing baseline cost (~$12/day) is eliminated, reliably
  and reversibly. **This is the main cost win and it stands.**
- **Option B — built, tested, REVERTED.** Created `biomate-nextflow-ce-spot` (SPOT,
  SPOT_CAPACITY_OPTIMIZED, VALID/healthy) and re-pointed both queues spot-preferred + on-demand
  fallback. **Spot placement works** — a cold job launched a real spot instance (`i-05a7088a92bc9f974`
  on `ce-spot`). **But that first spot job FAILED**: the spot instance was terminated mid-run and the
  Batch job (`f3d0ea9b`) exited FAILED with **`retryStrategy: null`** — the executor submits jobs with
  **no retry**, so a spot reclaim kills the job outright (no auto-retry to on-demand). Reliability/UX
  is the #1 priority, so I **reverted both queues to on-demand only** (VALID). The spot CE is kept
  **ENABLED but dormant** (no queue routes to it; min=0 → no cost) so it's ready to re-enable.
- **Option C — not done** (concurrent session's g5 training; not mine to kill).

### To make spot production-safe (required before re-enabling Option B)
Add a **Batch retry strategy** to the executor's job submission
(`backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`, where it registers/submits the job
definition): `retryStrategy` with `attempts: 2–3` + `evaluateOnExit` rules that **RETRY on host
termination / spot reclaim** (e.g. `onStatusReason: "Host EC2*"` → RETRY) and exit otherwise. With
that, a reclaimed task re-runs (on a fresh spot or the on-demand fallback) instead of failing the
user's job. Then re-point the queues spot-preferred and re-run the merfish/voyager validations to
confirm reclaim-resilience before trusting long pipelines. (Also consider Nextflow `errorStrategy
'retry'` at the process level as defense-in-depth.)

### Net state now
- Cost: always-on baseline removed (min=0). ✅
- Reliability: production on on-demand (unchanged from before). ✅
- Spot: CE exists + proven to place jobs; **gated on a retry strategy** before production use.
