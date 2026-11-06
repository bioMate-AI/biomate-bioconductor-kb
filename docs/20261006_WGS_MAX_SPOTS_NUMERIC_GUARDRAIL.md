# WGS Capstone: `max_spots` Numeric Guardrail — Root Cause and Fix

**Date:** 2026-10-07
**Branch:** `cursor/tutorial-live-recording-and-report-editing-4ea7` (the lineage deployed to dev)
**Commits:** `a07005fe5` (fetchngs S3 work-dir), `7ee9fd0c3` (numeric guardrail)
**Deploy:** synced to dev `2026-10-07 22:49` — `Sync OK at 7ee9fd0c (result=healthy)`

---

## 1. Symptom

The WGS capstone E2E (`frontend/e2e/wgs-capstone.e2e.ts`) routed correctly to a
germline variant-calling pipeline, began execution on AWS Batch, and then failed
early (~14 s in) during the SRA download stage. The run never reached GATK.

## 2. The prior diagnosis was stale

`docs/20260730` attributed WGS/SRA failures to the **nf-core/fetchngs** chain and
its work-directory handling. That diagnosis no longer matches current routing.

Verification this session: the WGS capstone routes to **`wgs_germline_gatk/main.nf`**,
which performs its **own** SRA retrieval through a `FASTERQ_DUMP` process
(`sra-tools`) — it does **not** go through the nf-core/fetchngs subworkflow, so
`_run_fetchngs_prefetch` is never on this path. The fetchngs code was not the
cause of the capstone failure.

## 3. Actual root cause

The failure was a malformed **numeric parameter**, not a storage/work-dir issue.

The LLM parameter extractor emitted `max_spots = "500000)"` — a value carrying a
trailing `)` that bled in from prose such as `"(max_spots=500000)."`. The
`wgs_germline_gatk` Groovy code coerces `max_spots` with `as int`, and
`"500000)" as int` throws a `NumberFormatException` (`For input string: "500000)"`),
which aborts `FASTERQ_DUMP` and fails the whole run.

Why the dirty value survived to the executor: in the schema-grounded extractor the
LLM-merge step never overwrites rule-filled keys, so once the dirty token was
present it was passed through to the workflow verbatim. There was no guardrail that
re-cleaned numeric-typed values before they reached Groovy.

## 4. Fix

### 4a. Numeric guardrail (`7ee9fd0c3`) — the fix for this failure

New function `coerceNumericParams` in `frontend/server/lib/paramRules.ts`, wired
into the schema-grounded path at `frontend/server/lib/schemaGroundedExtractor.ts`
as **Stage 3c-pre** (immediately before schema validation):

- For every schema param of `type: "number"`, if the value carries a digit but is
  not already a clean numeric token, extract the leading numeric token
  (int / float / scientific) and replace the value with it.
- Strips thousands separators (`"500,000" → "500000"`).
- Deliberately leaves **already-clean** values untouched, and leaves pure
  non-numeric sentinels (`"null"`, `"auto"`, `"none"`) untouched so a valid
  optional-numeric sentinel is never garbled into a dropped param.
- Emits one provenance note per changed value (`source: "rules", rule: "numeric-coerce"`)
  and logs `numeric-coerce <key>: "<from>" -> "<to>"`.

Trace on the failing case: `"500000)"` fails the clean-number test, matches the
numeric-token regex as `"500000"`, and is replaced — so `as int` receives
`"500000"` and no longer throws.

Tests: `frontend/server/paramRules-numeric-coerce.test.ts` — **7 cases** covering
the `max_spots="500000)"` case, thousands separators, scientific notation,
already-clean pass-through, and sentinel pass-through.

### 4b. fetchngs S3 work-dir (`a07005fe5`) — adjacent, still valid

`a07005fe5` runs the nf-core/fetchngs SRA pre-step on Batch with an S3 work
directory. This is correct and remains deployed + container-verified. It is the
right fix for **fetchngs-chain** SRA workflows — it simply was not the cause of
**this** capstone failure (see §2). Retained as a legitimate adjacent fix.

## 5. Validation status (honest)

| Check | Status |
|---|---|
| Fix correctness (code trace `"500000)" → "500000"`) | ✅ confirmed |
| Type check (`tsc --noEmit`) | ✅ clean |
| Unit/integration (`vitest`) | ✅ 1663 passed, incl. 7 new numeric-coerce cases |
| Deploy to dev | ✅ `Sync OK at 7ee9fd0c (result=healthy)`, smoke tests passed |
| Guardrail live in dev bundle | ✅ container-verified `numeric-coerce` present in `/app/dist/index.js` |
| End-to-end WGS Batch re-run clears the crash | ⚠️ **not terminally confirmed** |

On the last row: a WGS capstone re-run was launched against dev on real Batch, but
the driving harness terminated before its terminal verdict was captured. The
authoritative run logs reside on AWS Batch / CloudWatch, not inside the Galaxy
container; a read-only sweep of the Galaxy container's recent logs found **no**
`"For input string"` crash signature and no recent `.nextflow.log` (consistent
with the Batch-head execution model, so this is suggestive, not conclusive). A
fresh Batch run was **not** launched speculatively, per the no-speculative-expensive-runs
discipline — the fix is unit- and container-verified, and the failure mode it
targets is precisely the one observed.

## 6. Next step to fully close

To obtain the terminal E2E confirmation at controlled cost, the next WGS capstone
run that happens for any reason (scheduled suite, user-driven) should be checked
for the `[schemaGroundedExtractor] numeric-coerce max_spots` log line and a clean
`FASTERQ_DUMP` (no `NumberFormatException`). That converts the ⚠️ row to ✅ without
a dedicated speculative run.

## 7. CryoEM capstone — out of scope (infra-blocked)

The CryoEM capstone could not be exercised: the CryoSPARC GPU host
(`52.42.49.175:30000`) is down. This is an operations dependency, not a code
defect — no code change and no GPU spend were made.
