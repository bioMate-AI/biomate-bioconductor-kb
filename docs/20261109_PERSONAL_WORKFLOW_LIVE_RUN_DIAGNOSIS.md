# Personal (uploaded) workflow live-run — diagnosis (2026-11-09)

## What was tested
Closing the last execution gap on the uploaded-workflow feature with a **real
live run on dev** (the user approved "a full live run of an uploaded workflow …
it'll launch a small real Batch job"). Prior coverage (unit/e2e) mocks the
execution, so only a live run could exercise the dispatch→compute link.

Probe: a minimal personal `.nf` (`hello-liverun-probe`, 572 bytes) — one process,
one declared output, `container 'quay.io/biocontainers/python:3.11'` (proven
cached on dev Batch), trivial `python -c … > hello.txt` script.

## What happened — the wiring works, execution does not (on SaaS dev)
End-to-end, every personal-workflow-specific link **worked**:
1. `POST /api/workflows/upload-file` → stored in `personal_workflows`
   (id `f1a9d240-7354-4387-8493-c2ff3c2c65b0`). ✅
2. `POST /api/workflows/execute` with `workflowDefinition.personal_workflow_id`
   → Node fetched `file_content`, dispatched. ✅
3. Galaxy wrote the content to `/tmp/biomate_user_nf/<user>/<id>.nf` and launched
   Nextflow, which **parsed and executed** the `HELLO` process. ✅ (proves
   file_content → temp → dispatch is sound)
4. The process **failed at exit 127**: `.command.run: line 295: docker: command
   not found`. ❌

Run: `218ad8ec-485e-4284-b88b-46cc61bec566` (nf run `5bcc3291-…`), status
`failed`, 1 task failed, ~7 s.

## Root cause (ground truth from dev logs + container inspection)
Personal workflows are **deliberately forced onto the local executor**
(`nextflow_executor.py:7514-7531`):
```
# Personal workflows … must run locally — they are ad-hoc user scripts that
# don't carry BioMate's Batch process labels, and cannot initialise an S3 work dir.
if _nf_path_str.startswith("/tmp/biomate_user_nf/"):
    compute["executor"] = "local"
    params.pop("outdir", None); params.clear()
```
Dev log confirms the chosen path:
```
[Nextflow] Personal workflow — forcing local executor, cleared S3 outdir, cleared all params
cmd: nextflow run …/f1a9d240….nf -profile standard -w /tmp/nextflow_runs/…/work
[Nextflow] Generated on-prem local config (no MinIO)   # docker.enabled = true, executor local
```
The local executor runs each task via **docker on the Galaxy host**. But the
SaaS dev Galaxy container has **no docker**:
- `docker exec biomate-galaxy-dev which docker` → **NO_DOCKER_CLI**
- `/var/run/docker.sock` → **not mounted**
- no `SANDBOX_*` env

So the forced-local path has no container runtime to execute in → `docker: command
not found`. This is **not** environment-specific flakiness: uploaded workflows
**cannot execute on SaaS dev at all** under the current design.

Both `NEXTFLOW_USE_AWS=true` (galaxy + frontend) and `buildNextflowComputeConfig`
defaulting `executor='awsbatch'` are **overridden** by the force-local block at
7514 (comment: "This override must come AFTER the awsbatch routing block so it
wins"). The aws routing never applies to personal workflows by design.

## Why this was believed to work
`docs/20260706_PROJECT_AND_PERSONAL_WORKFLOWS_FULL_HISTORY.md` records the
"Run imported workflow → idle→running→completed" check as passing. That was in a
**docker-equipped environment** (local laptop with the docker socket, or an
on-prem deploy where the Galaxy container has docker). The design is correct for
on-prem; it was never exercised against the SaaS dev stack, where there is no
docker in the Galaxy container. The e2e suite mocks execution, so it couldn't
catch this either. The live run is what surfaced it.

## Options to actually make uploaded workflows run on SaaS
| # | Fix | Effort | Security | Note |
|---|-----|--------|----------|------|
| 1 | **Route personal workflows to AWS Batch** like catalog workflows (inject `process.executor='awsbatch'` + queue + s3 work dir; default ECR container for process-less tasks; keep the user's own `container` directive when present). | Medium (backend/lib executor) | **High concern** — runs arbitrary user Nextflow + arbitrary containers on BioMate Batch with the job IAM role. **Must** enable the existing sandbox pre-check (`validate_nextflow_source`, `SANDBOX_ENABLED` strict) + scope egress/IAM. | Honors user intent; my probe (self-contained container) would have run. |
| 2 | **Honest blocked state** — detect no local container runtime and return a clear launch error ("Uploaded workflows run via local container execution, not available in this environment") instead of a cryptic exit-127. | Low | None | Safe, shippable now; truthful, but does not make them run. |
| 3 | **Give the Galaxy container docker** (DinD or socket mount) on the EC2. | Infra | Runs user code on the shared host — same isolation concern as #1 without Batch's job-role boundary. | Not recommended. |

## Recommendation
**#1, gated by the sandbox validator in strict mode** — it's the only option that
delivers the user's stated requirement ("uploaded workflows should run in
BioMate") and reuses isolation infrastructure already in the tree. It is
security-sensitive (arbitrary user code on shared Batch), touches the executor
(`backend/lib/galaxy/**`), and needs the full pre-sync checklist + a careful
review, so it should not be flipped without an explicit decision. Ship **#2** as
an interim honesty fix regardless of the #1 decision, so the failure stops being
cryptic.

## Artifacts (for cleanup)
- Uploaded probe workflow `f1a9d240-…` (`hello-liverun-probe`) on the fixture
  account — safe to delete; left in place pending the execution-direction decision.
- Failed run `218ad8ec-…` — kept as evidence.
