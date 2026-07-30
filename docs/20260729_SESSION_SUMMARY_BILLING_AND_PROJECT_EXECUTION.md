# Session Summary — Flat-tier billing, billing-proxy fix, project multi-file execution fix + full project QA

**Date:** 2026-07-27 → 2026-07-29
**Branch:** all on `origin/integration/next-phase`
**Scope:** billing (Lago drop), a dev billing-proxy 401 root-cause + fix, a real project-execution bug
found by end-to-end testing and fixed, and a full project-module test pass.

---

## 1. Billing: Lago dropped from the critical path (flat-tier)

Billing now runs on **Stripe** (subscriptions/payment; sets `subscriptionTier`) + **internal quota**
(`DEFAULT_PLAN_LIMITS` in `quota_enforcer.py` + the Redis realtime ledger). Lago (usage metering) is
gated **off by default** (`BILLING_LAGO_ENABLED`), since flat-tier has no usage-based overage.

- `lago_client.lago_enabled()` (default off) → all emits no-op, quota reads return `None` (→
  `DEFAULT_PLAN_LIMITS`). `batch_event_handler._emit_to_lago` and `cost_log._forward_to_lago` gated too.
- The `cost_log→Lago` path was a **second, ungated** emitter found during live testing — every LLM call
  spawned a thread that blocked on a 5 s timeout against a stale Lago URL. Now gated.
- Verified live: `lago_enabled()=False` on dev; a UI chat records to the internal ledger with **zero**
  Lago forwards; `/api/billing/{usage,quota}` return real internal data.
- Detail: `docs/20260727_BILLING_LAGO_DROP.md`. CLAUDE.md Billing section updated (Lago = historical).

## 2. Billing-proxy 401 on dev — root-caused + fixed

Every `/api/billing/*` call 401'd on dev (`"Signature verification failed"`). Root cause: the Node
billing proxy re-signs the Galaxy JWT with `GALAXY_JWT_SECRET || JWT_SECRET`, and dev's
`GALAXY_JWT_SECRET` had drifted to a stale value while `JWT_SECRET` already matched Galaxy. Fixed on
dev (removed the stale override; container recreated) → `/api/billing/{quota,usage}` now **200**.

- **Invariant** (now documented in `scripts/setup_github_env.sh`): `GALAXY_JWT_SECRET` must equal the
  Galaxy backend's `JWT_SECRET`, or be unset.
- **Open handoff:** remove/correct the stale `GALAXY_JWT_SECRET` in the dev **GitHub secret** (the
  in-container fix isn't redeploy-durable) + verify the invariant in **prod** before the billing page
  is enabled. Spec: `docs/20260728_REQUIREMENT_GALAXY_JWT_SECRET_DURABLE_FIX.md`.
- Detail: `docs/20260727_BILLING_PROXY_JWT_401_ROOTCAUSE.md`.

## 3. Project multi-file execution bug — found by testing, root-caused + fixed + verified

Running a workflow from **project-uploaded** files failed at launch (~4 s). **Corrected root cause**
(an initial "empty params" diagnosis was wrong — completed runs also have empty `toolParameters`;
inputs live in `inline_parameters`): project files were passed as **bare filenames**
(`matrix=counts_matrix.csv`) instead of resolvable **S3 URIs**, and project files live in the app
bucket `S3_BUCKET_NAME` which AWS Batch cannot read. The demo chip works because it uploads files and
passes `s3://…` URIs; the project "Analyze" flow only lists filenames as text.

**Fix** (`frontend/server/routes.ts`, `/api/workflows/execute`): when a run has a `projectId`,
`resolveProjectFileParams()` matches bare-filename params against `project_files` and
`_stageProjectFileToNextflow()` does a cross-bucket `CopyObject` into `biomate-nextflow-work`,
substituting the resolvable `s3://` URI. Non-fatal on failure.

**Verified live:** the capstone run `9a92d0e4` **completed in 2m24s**; galaxy.log shows Nextflow got
`--matrix/--samplesheet/--contrasts s3://biomate-nextflow-work/uploads/project-<id>/…`; the report has
**real, biologically-correct DE results** (10 genes, complement cascade — the known AChR+ MG
pathophysiology). Detail: `docs/20260728_PROJECT_MULTIFILE_PARAM_MAPPING_GAP.md`.

## 4. Full project-module QA (live dev, no mocks) — 88 tests, 0 failures

Every element verified: create/rename/archive/delete, files (upload/delete/imports), members
(viewer/editor RBAC, leave, email invite), notes, share links (generate/join/revoke), member-vs-owner
authz, workspace (context injection, banner, tabs, Workflow Runs), collaboration UI.

Multiple real workflow use cases run to completion **through a project**:
- `nf-core/differentialabundance` → completed with real DE genes (the multi-file fix above)
- `predict_admet_properties` (iptacopan, conference CC5) → completed
- GWAS chain routing (CC7) in project context

Deep audit (screenshots, chat stream, outputs, report content) confirmed correct, honest presentation
in every state — including failure states (real error surfaced, "no outputs", failure-honest reports
with no fabricated results).

---

## Open follow-ups (documented, not blocking)

1. **[P1] Prod `GALAXY_JWT_SECRET` check** + remove stale dev GitHub secret — before enabling `/billing`.
2. **[P2] Guard:** block launching a workflow whose required *file* param is still unresolvable (surface
   the missing-input blocker) instead of a Batch launch failure.
3. **[P3] Stale `galaxyApiKey` → 500 on execute:** refresh proactively before the call, not after a 500.
4. **[deferred] Tier enforcement** (`TIER_ENFORCEMENT` on) + billing email notifications.

## Key commits (on `integration/next-phase`)

`0e0ff9d82` Lago drop · `d72900b09` cost_log gate · `9ea65fe7a` project file param fix ·
billing-proxy + JWT-invariant + requirement docs · `b517e9992` capstone regression test.
