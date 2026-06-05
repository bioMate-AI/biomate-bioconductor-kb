# Batch routing fixes (2026-06-04) + robustness backlog

**Branch:** integration/next-phase
**Triggering incident:** smoke run `5e7a2c52` (transcriptomic_moa_lincs) sat in RUNNABLE for 25+ min on `biomate-nextflow-queue` despite the CE having 32 vCPU / 63 GB free and the job needing only 1 vCPU / 1 GB. Forensics showed 12 jobs ahead in the queue, the 3 oldest being GPU workflows (`CPA_SYNERGY_GPU`, `GEARS_PERTURBATION_GPU`) that the CPU-only "optimal" EC2 CE could never satisfy. AWS Batch's FIFO scheduling stalled on the unscheduleable head-of-line, blocking every CPU job behind them.

## What landed

### 1. Code: default GPU queue routing
**Commit:** `3e1da7bed` — `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py:1572-1583`

```python
gpu_queue = (
    compute.get("gpu_batch_queue")
    or os.environ.get("GPU_BATCH_QUEUE", "")
    or "biomate-gpu-spot-queue"
)
```

Previously: if neither `GPU_BATCH_QUEUE` env var nor `compute.gpu_batch_queue` was set, the generated `nextflow.config` simply omitted the `withLabel: 'process_gpu' { queue = ... }` block. Every GPU-labelled process inherited the default queue (CPU-only), where it could never run.

Now: an explicit default catches the case nobody sets it on dev. Production override order is preserved (env > compute config > default).

### 2. AWS Batch: auto-cancel for stuck RUNNABLE jobs

Configured via `aws batch update-job-queue`:

```json
{
  "state": "RUNNABLE",
  "maxTimeSeconds": 1800,
  "action": "CANCEL",
  "reason": "MISCONFIGURATION:JOB_RESOURCE_REQUIREMENT"
}
```

Effect on `biomate-nextflow-queue`: any job stuck in RUNNABLE for >30 min is force-cancelled. Acts as the safety net for routing misconfigurations like the one Q1 fixed, and prevents indefinite FIFO stalls.

### 3. One-time cleanup
Cancelled the 12 head-of-queue stuck jobs (10 GPU, 2 CPU) that had been blocking the scheduler for ~10 hours. This was a one-shot — the auto-cancel policy and the routing fix together prevent the same situation from recurring.

## What this fixed at the system level

Earlier in the same day, smoke run `5e7a2c52` was held in RUNNABLE for 25+ minutes despite a healthy CE with massive free capacity. After cancelling the head-of-queue GPU jobs, the same run advanced to STARTING within seconds. The bottleneck was never capacity — it was routing.

The Playwright e2e `bjibhqyr1` audit (run by parallel session, scope outside this commit) is the system-level validator that everything plays nice together.

---

## Robustness backlog — what else would help

Concrete, prioritized. The fixes above closed the *acute* hole; below is what would harden the system against the *next* category of failure.

### Tier 1 — high leverage, low effort

1. **Auto-cancel for STARTING too.** RUNNABLE auto-cancel catches misrouted jobs; STARTING auto-cancel catches stuck container pulls (e.g. ECR rate limits, broken `biomate/<name>-nf:1.0` images). Same `update-job-queue` call, add a second action with `state: "STARTING"`. Recommended `maxTimeSeconds = 900` (15 min — much shorter; pull should take <5 min).

2. **Job retry policy.** All BioMate `attempts: []` (single-attempt). Spot reclaim or transient ECR error → instant fail. Set `retryStrategy.attempts = 2` in the auto-generated job def, with `evaluateOnExit` matching `STATUS_REASON ~ Spot|ECS|DockerTimeoutError` to retry only transient failures. Permanent failures (workflow code error, exit code != 0) shouldn't retry.

3. **publishDir verification sweep.** Galaxy already has the 12h stuck-running guard. Add a complementary post-completion check: when a workflow reports `status=interrupted` AND `returncode=-6` (SIGABRT), grep the workflow-trace.txt for `COMPLETED  0` rows — if the underlying Batch task succeeded, sweep `work/*/COMPLETED-task-dir/*` to `outputs/<run_id>/` directly with `aws s3 sync`, then mark Galaxy status as `completed`. This is a *recovery* path for the residual publishDir crashes we still occasionally see.

4. **CloudWatch dashboard for queue health.** Three metrics, one panel:
   - `aws.batch.SubmittedJobs` per queue
   - `aws.batch.JobQueueDepth` per queue (RUNNABLE+STARTING)
   - Custom: p95 time-from-SUBMITTED-to-RUNNING per queue
   Threshold alarm on p95 > 300s would have flagged today's stall in minutes.

### Tier 2 — meaningful, medium effort

5. **Per-workflow image pre-pull.** First-time ECR pull of a 4-GB GPU image on a fresh Batch instance is 60–180s. For frequently-used workflows, add a `cloud-init` script to the launch template that pre-pulls `biomate/transcriptomic-moa-lincs-nf:1.0`, `biomate/cpa-synergy-gpu-nf:1.0`, etc. before joining the ECS cluster. Cuts dispatch latency in half for cold-instance scenarios.

6. **Mixed Spot+On-Demand allocation for GPU CEs.** `biomate-gpu-spot-v1` is 100% Spot. Spot reclaim mid-run = lost work + Nextflow's retry storm. Configure the CE with `allocationStrategy = SPOT_CAPACITY_OPTIMIZED` and `bidPercentage = 100` + a fallback CE of On-Demand g4dn. Workflow-level retry (#2) provides the second line of defense.

7. **Multi-AZ CE subnets.** Spot pool depletion is AZ-correlated. CEs currently target a small subnet set. Spread across all 4 us-west-2 AZs. Cheap, no code change, just CE config edit.

8. **CE redundancy per queue.** Single-CE queues are a SPOF — if `biomate-nextflow-ce-v2`'s instance role gets revoked, IAM rotates, or AMI is deleted, the whole queue stalls silently. Add `biomate-nextflow-cpu-v5` (which already exists, currently unattached) as a second CE on `biomate-nextflow-queue` at order=2. Batch fails over automatically.

### Tier 3 — strategic, larger effort

9. **Separate queue per workflow class.** Already partially true (CPU vs GPU). Could go further: `biomate-nextflow-light-queue` (1-vCPU pharmacology models, RUNNABLE max 5 min) vs `biomate-nextflow-heavy-queue` (GPU MD sims, RUNNABLE max 60 min). Different auto-cancel policies, different priorities, different CEs. Today they all share `biomate-nextflow-queue` with one priority, one timeout.

10. **Workflow-level publishDir replacement.** The recurring JVM SIGSEGV at `S3TransferManager.<init>` is fundamentally an upstream bug (glibc 2.41 + JDK 21 + AWS CRT native lib). Until Debian / OpenJDK ship the fix, we keep papering over it (CRT cache, Xss2m, FD-decouple, LD_BIND_NOW). The strategic fix is to **stop using publishDir to S3**: emit results to `work/` only and have Galaxy post-pull them via the existing `run:<runId>:datasets` virtual-history URI scheme (already in `routes.ts:2898`). Eliminates a fragile NF code path entirely.

11. **Cost/time observability per workflow.** We bill via Lago for vCPU-hour, but a per-workflow breakdown ("ADMET avg 38s, $0.002; CryoSPARC SPA avg 35 min, $1.20") would let users + ops make informed routing decisions. Already partially in `billing_router.py`; surface in a /admin dashboard.

12. **NF version pin self-test.** Today's pre-mortem showed the NF version drifting from 25.10.5 to 26.04.2 silently (`sync_to_dev.sh` version check had a Permission Denied that masked the drift). Add a pre-flight check on Galaxy boot: `nextflow -version` and assert `25.10.5`. Fail health check loudly if drifted.

## Acceptance criteria for "Batch is robust"

For the user-facing claim "BioMate Batch jobs reliably complete":

- ✅ p95 SUBMITTED → RUNNING < 60s (under load)
- ✅ 99% of submitted jobs reach a terminal state within 1 hour (or fail loudly)
- ✅ Zero misrouted jobs (auto-cancel + sensible defaults)
- ✅ Spot reclaim transparent to the user (workflow-level retry)
- ✅ Cold-instance dispatch < 90s (image pre-pull or warm-pool)
- ✅ Visible queue-depth + dispatch-latency metrics in CloudWatch

Today's commit closes the routing slice. Tier 1 items 1–4 close the next ~70% of the gap.
