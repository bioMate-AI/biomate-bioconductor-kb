# 20260713 — Prod release checklist: dev-search + Nextflow param fixes

What must reach **prod** to close the bugs verified on dev this session. All three fixes are
already merged to `integration/next-phase`; prod still runs the old code.

## What's being shipped (all merged to integration/next-phase)

| PR | Fix | Prod impact if NOT deployed |
|----|-----|------------------------------|
| **#96** | Executor serializes list/dict params as **JSON, not `str()`** (`nextflow_executor.py`) + hard-gated CI guard | Any workflow with a list/dict param (SMILES lists, etc.) silently mis-parses → tool gets a bogus single value → crash / RDKit fallback. ~272 workflows. **This is the ADMET root cause.** |
| **#97** | Fork-after-threads deadlock → embedding warmup moved to gunicorn `post_fork`; ADMET routing runnable-gate | `/api/workflows/search` (and chat routing) hangs forever under `--preload`; ADMET/biomate-tool queries route to the wrong workflow |
| #95 (optional, still open) | biomni-admet Dockerfile version lock + reusable build+smoke CI framework | Container dep drift can silently re-break image builds. Not a functional prod blocker (the `:x86` image in ECR is already the fixed build) |

## Deploy steps

1. **Backend image** — the critical one. Build the prod backend from `integration/next-phase`
   (or merge to `main` per your release flow) and deploy. This carries #96 + #97 (executor param
   serialization, post_fork warmup, routing gate).
2. **No env hack needed.** #97 makes the warmup fork-safe, so prod does NOT need
   `WORKFLOW_SEARCH_WARMUP=false` (the dev hot-patch). The code default (warmup on) is now safe.
3. **ADMET container** — `biomate/biomni-admet:x86` in ECR is already the fixed image
   (numpy<2 / chemprop 1.6.1 / admet-ai 1.3.1, lockfile). Prod Batch pulls `:x86` on a fresh
   compute instance. ⚠️ AWS Batch caches mutable tags — if a prod Batch instance has an old `:x86`
   cached, cycle the compute env's instances (no jobs running) or rely on it landing on a fresh
   instance. The **executor fix (#96) is what actually makes ADMET produce real output**; the
   container is secondary.

## Post-deploy verification on prod (do all)

```
# 1. search doesn't hang, returns fast, routes correctly
POST /api/workflows/search  {"query":"ADMET properties prediction for a compound"}
  → 200 in a few s, workflow_name = "Predict ADMET Properties (AI)" (NOT destiny_projection)
POST /api/workflows/search  {"query":"RNA-seq differential expression"}   → 200, no hang

# 2. ADMET runs end-to-end with the REAL model (the param-serialization fix)
execute predict_admet_properties  smiles_list=["CC(=O)OC1=CC=CC=C1C(=O)O"]
  → toxicity_report.json estimation_method == "admet_ai_chemprop"  (NOT rdkit_descriptors)
  → results.json is real predictions (NOT "ADMET-AI error ... Falling back to RDKit")
```

## Rollback

Backend deploys are image-tag swaps — roll back to the previous prod tag. No data migration.

## Notes / provenance

- Root cause diagnosis + evidence: memory `dev-search-fork-deadlock`; the "too many indices" →
  executor `str()` chain was cracked via the Batch job's CloudWatch stderr (`/aws/batch/job`).
- The methodology (upstream-hunt + close-the-class) is captured as the `systemic-root-cause` skill.
