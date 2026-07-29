# Finding: multi-file inputs not mapped to workflow params via the project upload→run path

**Date:** 2026-07-28
**Status:** 🟡 Root-caused (real gap) — fix not yet started
**Severity:** P2 — blocks running multi-file workflows (differentialabundance, etc.) from a project without manual param entry
**Found by:** `frontend/e2e/project-real-run-capstone.e2e.ts` (real GSE227835 counts through a project)

---

## What was tested

Real capstone: upload the curated **GSE227835** MG counts to a **project** (counts_matrix.csv +
sample_metadata.csv + contrasts.csv) → "Analyze with BioMate" → chat → route → Run → expect a
**completed** `nf-core/differentialabundance` run with real DE genes.

## What happened

- ✅ **Routing is correct** — the chat routed to `nf-core/differentialabundance` (chip confirmed).
- 🔴 **The run failed at launch** — wall time **4 s**, report abstract: *"premature pipeline execution
  failure … yielding 0 significant genes."*
- 🔴 **Root cause:** the run record shows **`parameters: {"version":1,"toolParameters":{}}` — empty.**
  The three uploaded files were **never mapped** to differentialabundance's required params
  (`matrix` / `samplesheet` / `contrasts` = counts_matrix.csv / sample_metadata.csv / contrasts.csv).
  The workflow launched with **no inputs** → immediate failure.
- ⚠️ **Secondary (transient):** the test's retry hit a `500` on execute — Node logged
  `[auth] User …163.com galaxyApiKey is stale (HTTP 500) — clearing + re-provisioning`. Self-healing
  (stale Galaxy API key re-provisioned); not the primary cause, but worth noting it surfaced.

## Why this is a real gap (not just a test artifact)

- The **curated MG demo chip** (conference default) runs this exact dataset+workflow successfully —
  so the capability exists; the demo chip maps the 3 files to their param roles specially.
- The **generic project path** (upload files → "Analyze" → chat → Run) does **not** carry that
  role-mapping: `toolParameters` comes through empty. A user who uploads the exact files a workflow
  needs and asks to "run differential expression" gets a run with zero inputs.
- Single-file workflows partly mask this: UC-PW2 (nf-core/rnaseq, one FASTQ) reached TRIMGALORE (got
  its input) and failed only on the synthetic data. **Multi-file, role-specific inputs are where the
  mapping is missing.**

## Proposed fix (scope)

Wire project-uploaded files into workflow params on the analyze/route path, by **role**:
1. When a workflow is routed with project files in scope, map files to required params by
   name/extension/role heuristics (matrix = counts*, samplesheet/observations = *metadata/samples*,
   contrasts = contrasts*), mirroring what the MG demo chip does — but generically.
2. Fall back to an explicit "map files to inputs" UI step when heuristics are ambiguous, instead of
   launching with empty `toolParameters`.
3. **Guard:** never launch a workflow whose required params are unset — surface the missing-required
   blocker (the panel already has this for other cases) rather than a 4-second Batch failure.

Also (separate, smaller): investigate the stale-`galaxyApiKey` → 500 on execute; re-provisioning
works but a stale key should be refreshed proactively before the execute call, not after a 500.

## Verification hook

`frontend/e2e/project-real-run-capstone.e2e.ts` is the regression test — it asserts a **completed**
run + a report containing real DE results. It currently fails at the empty-params launch; when the
mapping is fixed, this test turns green. (Marked `fixme` until then so it doesn't red the suite.)

## Not affected

Routing, project CRUD, collaboration/RBAC, context injection, single-file rnaseq linkage, and the
billing/Lago work are all verified green. This gap is specific to **multi-file input→param mapping in
the project execution path**.
