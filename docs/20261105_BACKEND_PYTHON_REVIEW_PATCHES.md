# Backend-Python review patches (audit sweep: QC gates + billing)

> ## ⚠️ COMMITTEE CORRECTIONS (Fable, 2026-11-05)
> - **B4 (GOLD on zero gates) — real but NOT a live "perfect pass" bug; it's latent hygiene.** `all([])→True`,
>   `overall="GOLD"` is confirmed in `qc_gate_reader.py:541-551`, BUT the claimed reach via
>   `nextflow_executor.py:4506-4508` is wrong — `gate_checker` takes `build_gate_event(...).get("gates", [])`
>   and DISCARDS `passed`/`overall`, so an empty list is just no rows; and the live emitter
>   `qc_gate_emit.py:154-155` returns False on empty `gates` (no GOLD event). The only consumer of
>   `passed`/`overall_level` is a docstring example. The `NOT_EVALUATED` fix is good hygiene, not an
>   active bug — downgrade its priority.
> - **B6 (`inf` quota) — symptom confirmed, MECHANISM in the doc is wrong.** Starlette's `JSONResponse.render`
>   uses `allow_nan=False`, so FastAPI raises `ValueError: Out of range float values are not JSON compliant`
>   → **HTTP 500** (it never emits an `Infinity` token for the browser to reject). The Node proxy passes the
>   500 through. The `null`-for-unlimited fix is correct regardless; **verification must look for a 500**, not
>   a client JSON.parse error.
> - **B8** — the lazy re-derive fix has an existing hook: `internal_set_plan` (`billing_router.py:631-645`)
>   already delegates to `ensure_quota_set`.
> - B1/B2/B3/B5/B7 CONFIRMED as diagnosed (B1 note: after the `.nf` DILI patch, the label/number are coupled by
>   one bucketer, so B1 becomes a threshold-harmonization task — `.nf` "high" ≥0.65 vs gate HALT ≥0.8).


**Not applied.** Backend-Python fixes a human applies + verifies. From the 2026-11-05 audit
(surfaces 2 QC and 5 billing). Line numbers from the audit's code trace — verify exact lines on
apply (the backend tree moves). Each: root cause, fix sketch, verification.

## QC gate engine

### B1. DILI gate HALTs on the categorical `dili_risk` label, ignoring numeric probability — patient-safety
`backend/lib/galaxy/jobs/qc_trace_monitor.py` (~5493-5509 gate; ~2018-2022/3777-3780 metric read).
The gate fires HALT when `dili_risk == "high"` OR `dili_probability >= 0.8`, reading a single
top-level `toxicity` block (a worst-of-set label for a multi-SMILES run). A compound with
`dili_probability` 0.041 but aggregate `dili_risk="high"` is HALTed on the string despite the
numeric evidence being a clear pass (the gate side of the DILI incident).
**Fix:** gate on the numeric `dili_probability` as primary; treat categorical `dili_risk` as
advisory only (or require per-compound provenance so a low numeric probability can't be overridden
by an aggregate label). Pair with the `.nf` per-compound provenance fix (C5). Verify: a low-DILI
compound with a stale "high" aggregate label PASSES the DILI gate.

### B2. hERG probability-only predictions bypass the cardiotox gate on the S3/Batch path — patient-safety
`nextflow_executor.py:_extract` (~4744-4748) copies `herg_ic50_uM, dili_risk, dili_probability,
ames_positive, ames_probability, clintox_probability` but DROPS `herg_inhibition_prob` that the
live in-process parser (`qc_trace_monitor.py:~2008-2011`) reads. A workflow predicting only a hERG
inhibition probability (no IC50) has its `herg_prob >= 0.9` gate never evaluated on completion/S3
runs → recorded as a clean pass; the live and completion paths disagree.
**Fix:** add `herg_inhibition_prob` (and any other keys the live parser reads) to the `_extract`
allow-list so both paths evaluate the same metrics. Verify: a prob-only hERG output HALTs on both
the live and the reopened/completion path identically.

### B3. `FASTP` registered with `"*.json"` mis-attributes any JSON to a sequencing gate — data-integrity
`qc_trace_monitor.py:~1714` `"FASTP": ("fastp", "*.json")`. In `_reconstruct_qc_from_s3`
(`nextflow_executor.py:~4530-4546`) `"*.json"` matches any basename not excluded by the
`{qc_metrics.json, qc_report.json}` guard, so a clinical/chem run's JSON with no other recognizable
process name is attributed to FASTP → a sequencing-QC gate row on a clinical domain (the
FASTP-on-clinical incident).
**Fix:** use the real fastp basename (`fastp.json` / `*.fastp.json`), or exclude the over-broad
`"*.json"` from the process-inference candidate set the way `qc_metrics.json` already is. Verify: a
clinical run no longer emits a FASTP gate row.

### B4. `build_gate_event` returns GOLD / passed=True when ZERO gates evaluated — scientific-correctness
`qc_gate_reader.py:~541-558`: `all_passed = all(gate_results)`; `all([]) == True` → `overall="GOLD"`.
Reachable via `nextflow_executor.py:~4506-4508` (`gate_checker` path). A run whose metrics are all
absent/misnamed → "perfect pass", violating the repo rule "a gate that cannot be read must never
read as a pass."
**Fix:** when `gate_results` is empty, return `passed=None` / `overall="NOT_EVALUATED"`; have
`assess_qc_document` surface not_evaluated (which the frontend now renders — audit S2#5). Verify: a
run with no readable QC metrics shows NOT_EVALUATED, not GOLD.

### B5. `read_bioc_harness_gates` signature-incompatible with `build_gate_event` — latent (data-integrity + crash)
`qc_gate_reader.py:~773` registers a `list[tuple]`-returning fn in a registry whose consumer
(`~525-540`) unpacks a single 6-tuple (`gate_name, value, threshold, passed, level, msg = result`),
outside the try/except. Currently unreachable (`classify_gate_only_domain` has no `bioconductor_qc`
mapping), so bioc QC-harness gates silently never surface; if ever wired it raises ValueError out of
the ungated `gate_checker` call.
**Fix:** flatten list-returning gate fns in the registry consumer, or wrap `read_bioc_harness_gates`
to conform to the single-tuple contract. Verify: a bioc QC run surfaces its gate rows without error.

## Billing

### B6. `float('inf')` quota serialized as JSON `Infinity` → billing page dead for unlimited tiers — ship-blocker
`quota_enforcer.py:~46-48,112-115` (inf limits) → `realtime_cost_service.py:~531,538` (`quota_usd =
float(limit)`) → `billing_router.py:~234,278`. Starlette emits the token `Infinity`; the browser's
`JSON.parse` rejects it → `/api/billing/usage` and `/api/billing/quota` both fail to parse → billing
page errors out for team/enterprise/test tiers.
**Fix:** serialize unlimited as `null` (or omit the field) in `get_current_costs`/quota endpoints;
never return `inf`. (The frontend already treats `quota_usd: null` as unlimited.) Verify: an
enterprise user's `/api/billing/usage` is valid JSON with `quota_usd: null`.

### B7. Redis-down `/usage` fallback returns a flat shape missing `month`+`breakdown` → page throws — UX
`billing_router.py:~213-219` returns flat `{llm_cost_usd, compute_cost_usd, storage_cost_usd,
total_usd, quota_pct, redis_status}` while the consumer (`billing.tsx` `cycleLabel(usage.month)`,
`usage.breakdown.*`) expects the nested canonical shape → `cycleLabel(undefined).split('-')` throws
exactly when the comment says the page should "remain usable."
**Fix:** return the canonical zeroed shape (same keys as `get_current_costs`, with
`redis_status:"unavailable"`). Verify: with Redis down the billing page renders a zeroed usage view,
not an error boundary.

### B8. Month-rollover fail-open (quota not repopulated) — billing-integrity (PLAUSIBLE; live-verify)
`realtime_cost_service.py:~535-538` keys the limit `quota:{uid}:month:{YYYY-MM}:limit` and only
(re)sets it on login/plan-change/webhook. A continuously-authed user (long-lived JWT / API) crossing
a month boundary has no `:limit` key for the new month → `quota_usd=None` → `check_and_reserve`
allows unlimited and `/quota` reports `over_quota=false`.
**Fix:** on a quota read-miss, lazily re-derive the limit from the user's plan (`ensure_quota_set`)
before returning None. Verify (live): GET `/api/billing/quota` for a fixture early in a fresh month
returns a non-null `quota_usd`.

### B9. `used_usd` / `quota_pct` include in-flight running ESTIMATES, not just committed — semantics (decide)
`realtime_cost_service.py:~530-532` `total_usd = committed + running_estimate`; `/quota` gates (402)
on this. A long-running Batch job is gated on a polled estimate that may over/under-shoot the final
cost. Likely intentional (conservative), but `committed_usd` exists separately if "used" should mean
committed-only. **Action:** confirm the intended definition; if enforcement should be on committed
spend, base `used_usd`/the 402 gate on `committed_usd` and expose the estimate separately.

---
Priority: B1/B2 (patient-safety QC gates), B6/B7 (billing ship-blockers), then B3/B4, B5, B8/B9.
