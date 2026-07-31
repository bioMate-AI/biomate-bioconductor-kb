# WGS + Cryo-EM launch failures — root causes + fixes

**Date:** 2026-07-30
**Status:** both root-caused (via parallel agents) + code fixes shipped. WGS fix is verifiable on dev;
Cryo-EM end-to-end is blocked on an **infra prerequisite** (AMI rebuild).
**Supersedes the "WGS = required-input param" guess in** `docs/20260730_WGS_CRYOEM_UI_E2E_FINDINGS.md`
(that guess was wrong — params were correct).

---

## WGS — NOT a WGS bug: a transient launch race (fixed)

**Definitive error:** the `execution_runs` row for `634d6eea` had
`execution_json.error = "fetch failed"` — a Node/undici transport error. The pipeline **never
launched**: no `nextflow_run_id`, no `[Nextflow run …] cmd:` line anywhere in galaxy.log, steps 0/0.

**Root cause:** the frontend launch POST (`routes.ts` → `POST ${GALAXY_URL}/api/nextflow/execute`)
coincided with a **gunicorn worker-pool recycle** (`--workers=4 --max_requests=3000`). The pool took
~50 s to come back accepting connections; the retry loop was only **3 attempts × 3 s ≈ 6 s** (its
comment wrongly assumed "recycles in <5s"), so all 3 hit ECONNREFUSED → `fetch failed` → the run was
marked failed with 0 steps. This affects **any** workflow launch that races a recycle, not just WGS.
Params (`reads=SRR1518169`, igenomes reference) were correct and irrelevant to the failure.

**Fix (`frontend/server/routes.ts`, Nextflow-direct launch loop):** widen the retry budget to
**7 attempts with backoff `[0,3,5,8,12,15,15]s` (~58 s)** so it outlasts a full worker recycle,
retrying `fetch failed`/ECONNREFUSED/ECONNRESET and 502/503/504 across the window. Low-risk, general
launch-resilience improvement.

> Complementary durable fix (not done here): a launch POST landing mid-recycle has no idempotent
> server-side landing pad — a `CompletionPoller`-style reconciler could accept a "queued" run and
> retry the Galaxy submit out-of-band (mirrors the read-side design in
> `docs/20260615_RUNS_PERSISTENCE_DESIGN.md`). Widening the retry is the targeted fix.

## Cryo-EM — single always-on CryoSPARC master + a stale AMI (code fix + infra prerequisite)

**Root cause:** the cryo SPA chat path submits GPU jobs to AWS Batch, but every task connects to a
**single CryoSPARC master host** (`cryosparc_host:30000`). On dev that host isn't serving. The chat
path called `start_instance(wait=True)`, which returns as soon as EC2 is `running` — **before** the
CryoSPARC API is listening — so Batch tasks race a half-booted (or absent) master and fail.
`use_cryosparc=false` is **NOT** an escape hatch: it's a `random.uniform()` **mock** that fabricates
resolution/FSC — routing to it would ship fake science (forbidden), so we don't.

**Fix (`backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`, provisioning block):**
- Provision path now calls **`ensure_cryosparc_running()`** (under `_INSTANCE_LOCK`) which provisions
  or reuses the instance **and blocks until the CryoSPARC API actually answers** (15-min budget) —
  instead of trusting EC2 `running`. On failure → 503 (never mock).
- Permanent-host path (`CRYOSPARC_SKIP_PROVISION`) now **health-checks the host's port first** and
  fails fast with a clear 503 if it's down, instead of letting every Batch task fail opaquely.
- No always-on host is assumed; the on-demand instance idle-terminates after the run.

**Infra prerequisite (BLOCKS end-to-end on dev — ops, not code):** `CRYOSPARC_AMI_ID` on dev is
`ami-008607f719aaac1b0`, which **no longer exists** (`DescribeImages` → `InvalidAMIID.NotFound`), and
there are no self-owned CryoSPARC AMIs in the account. On-demand launch cannot succeed until a current
CryoSPARC AMI is built and `CRYOSPARC_AMI_ID` repointed. Until then the code fix makes cryo **fail
fast with a clear reason** rather than hang/fail opaquely — but it cannot *complete* on dev.

## Verification

- tsc clean; `vitest` 978 passed; `nextflow_executor.py` compiles on py3.9.
- **WGS launch fix — VERIFIED (2026-07-31):** after deploy, the re-run **launched** (galaxy.log has
  the `nextflow run …/wgs_germline_gatk/main.nf -profile aws …` cmd; no more "fetch failed"). The
  retry-budget fix works.
- **WGS — NEW remaining blocker (revealed by the launch fix):** the run now fails at ~10 s because the
  reference genome is passed as the **bare string `--reference hg38`** instead of the S3 FASTA path
  (`s3://ngi-igenomes/igenomes/Homo_sapiens/UCSC/hg38/Sequence/WholeGenomeFasta/genome.fa`). BWA/GATK
  can't open a reference named "hg38". The genome-alias → S3-FASTA resolution is **inconsistent** —
  the very first failed run (`634d6eea`) had the full S3 path in its params, this run got the bare
  alias. **Next fix:** make `reference` deterministically resolve genome aliases (hg38/GRCh38/…) to
  the igenomes FASTA S3 path (rule-based, per CLAUDE.md "canonical alias normalization"). WGS test
  stays `fixme` until then.
- **Cryo-EM:** remains `fixme` until the AMI is rebuilt; the code fix is verified by review + compile
  (can't complete end-to-end without the AMI).

## Handoff (infra/ops)

1. Rebuild the CryoSPARC AMI and repoint dev `CRYOSPARC_AMI_ID` (Cryo-EM end-to-end blocker).
2. (Related, from the billing session) prod `GALAXY_JWT_SECRET` invariant + dev GitHub-secret cleanup.
