# ADMET DILI aggregation fix — review patch (BUG #1)

**Not applied.** This touches a production `.nf` (embedded Python executed by Nextflow); per CLAUDE.md a human applies + verifies with a live ADMET run. This is the exact, drop-in change + the why + the expected before/after.

## The bug (recap)
`backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/predict_admet_properties/main.nf`, lines **479-485**: the top-level `toxicity.dili_probability`/`dili_risk` are seeded by a Phase-1 RDKit logP heuristic (`0.55 + 0.05*(logP−4)` → 0.672 for terfenadine, "high"), and the Phase-2 ADMET-AI override is an **asymmetric `if/elif` with no `else`**:

```python
            # DILI: override heuristic when ADMET-AI gives clearer signal
            if dili_p >= 0.65:
                tox_report["toxicity"]["dili_risk"]        = "high"
                tox_report["toxicity"]["dili_probability"] = round(dili_p, 3)
            elif dili_p >= 0.40 and tox_report["toxicity"].get("dili_risk") != "high":
                tox_report["toxicity"]["dili_risk"]        = "medium"
                tox_report["toxicity"]["dili_probability"] = round(dili_p, 3)
```

For terfenadine `dili_p = 0.0408` (the ADMET-AI worst-compound value): `0.0408 >= 0.65` false, `0.0408 >= 0.40` false → **neither branch fires**, so the stale 0.672/"high" survives. hERG (line 442) and clintox (443) are set **unconditionally** from the AI worst value — which is why hERG is correct and DILI is not. The stale aggregate is then read by `qc_metrics.json` (`main.nf` ~789-815 → `admet_dili_probability_passes = (dili_risk != "high") and dili_prob < 0.5`) and by the executor's QC-card builder (`nextflow_executor.py` `_extract` ~4741 / `_pass_or_fail` ~4855) → the **DILI safety gate is recorded FAILING** though the compound passes (0.041 < 0.5). And `per_compound` is synced to the AI value (0.041) via `_dili_bucket_from_prob` (lines 500-521), so aggregate ≠ per-compound for n=1.

## The fix
`_dili_bucket_from_prob(dp)` (lines 500-506) already buckets low/<0.40 → "low", 0.40-0.65 → "medium", ≥0.65 → "high" — it's just defined *after* the aggregate block and never used there. Make the aggregate call it **unconditionally**, the same way per_compound does, so aggregate == per-compound by construction.

**Step 1 — move the helper above the DILI block.** Cut the `def _dili_bucket_from_prob(dp): …` (lines 500-506) and paste it just before line 479 (right after the hERG-IC50 block ends at line 477).

**Step 2 — replace lines 479-485** with an unconditional set using the helper:

```python
            # DILI: use the ADMET-AI worst-compound probability UNCONDITIONALLY (like
            # hERG/clintox above), via the SAME bucketer per_compound uses, so the
            # aggregate ALWAYS equals the per-compound value and never retains the stale
            # Phase-1 RDKit logP heuristic. The old asymmetric if/elif (no else) left a
            # LOW AI DILI (<0.40) on the heuristic — e.g. terfenadine's real DILI 0.041
            # did not overwrite a stale 0.672/"high", wrongly FAILING the DILI QC gate
            # (qc_metrics.json and the after-run QC card both read this aggregate).
            _dili_risk, _dili_prob = _dili_bucket_from_prob(dili_p)
            tox_report["toxicity"]["dili_risk"]        = _dili_risk
            tox_report["toxicity"]["dili_probability"] = _dili_prob
```

**Step 3 — remove the now-duplicate** `def _dili_bucket_from_prob` at the old location (lines 500-506), since it moved up in step 1. The `for pc in tox_report.get("per_compound") …` loop at 508 keeps calling it, now from the moved-up definition.

(Optional hardening: the per-compound sync loop only runs `if match.get("DILI_prob") is not None`; the aggregate `dili_p` comes from `worst_dili.get('DILI_prob', 0) or 0`, so a fully-absent DILI_prob makes `dili_p = 0` → "low". If "no DILI signal" should be distinct from "low", guard the aggregate set with `if per_compound_admet:` — but for the current bug, bucketing 0 → low is acceptable and safe.)

## Expected before → after (terfenadine, 1 compound)
| field | before (bug) | after (fix) |
|---|---|---|
| `toxicity.dili_probability` | 0.672 | **0.041** |
| `toxicity.dili_risk` | "high" | **"low"** |
| `qc_metrics.admet_dili_probability_passes` | **false** | **true** |
| after-run DILI gate | **FAILED** | **PASS** |
| aggregate vs `per_compound` (0.041) | mismatch | **equal** |

hERG is unchanged (already correct: 0.977 / IC50 0.0103 µM → gate correctly flags cardiotox).

## Same bug elsewhere — ⚠️ CORRECTED (committee Fable, 2026-11-05): the "identical fix" does NOT transfer
- `backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/ADMET_pred/main.nf` (~274-280) — the
  override there derives DILI from a DeepPurpose **ClinTox** probability; there is **no DILI model** in that
  file. Making that set *unconditional* would define `dili_probability := clintox_prob` for EVERY compound,
  conflating two endpoints — a new bug, not the same fix. **Do NOT apply the identical change here.** Instead
  either leave the asymmetry, or (better) drop the ClinTox→DILI override entirely and compute DILI from a real
  DILI source. This caveat applies to the byte-identical `_archived/drug_discovery/ADMET_pred/main.nf` too.
- The primary fix in this doc (`predict_admet_properties/main.nf`) is CONFIRMED correct by the committee.

## Verification (human, after applying)
Run a live ADMET workflow on a known low-DILI/high-logP compound (terfenadine is the canonical case). Confirm in the output `toxicity_report.json` that `toxicity.dili_probability == per_compound[0].dili_probability` and that `qc_metrics.json.admet_dili_probability_passes == true`, and that the after-run QC card shows the DILI gate PASS (not FAIL). hERG must remain flagged.
