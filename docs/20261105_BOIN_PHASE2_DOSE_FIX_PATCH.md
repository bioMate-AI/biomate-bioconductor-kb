# BOIN Phase-2 dose above MTD — review patch (BUG #2)

**Not applied.** Production `.nf` (embedded Python executed by Nextflow) under
`nextflow_nfcore/subworkflows/` — per CLAUDE.md a human applies it and verifies with a live
`clinical_trial_simulation` run. This is the exact root cause + drop-in fix + expected before/after.

File: `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/clinical_trial_simulation/main.nf`

## The bug — recommends a Phase-2 dose ABOVE the trial's own MTD (patient-safety verdict)
Observed (run `c93845cd`): `true_MTD_dose_mg = 20` (40 mg flagged overdosing; 40 mg DLT 0.362 ≥
its 0.325 de-escalation boundary) yet `recommended_Phase2_dose = "40 mg QD"`.

Root cause, lines **296-328**:
- `p2_base = doses_to_use[true_mtd_idx]` (296-298) — the Phase-2 base IS the BOIN-identified MTD. Good.
- **304:** `for dose_mg in [p2_base, p2_base*0.5, p2_base*2.0]:` — the candidate set includes
  `p2_base*2.0`, i.e. **2× the MTD**.
- **305:** `if dose_mg > max_dose * 1.1: continue` — the only cap is the dose-RANGE maximum, NOT
  the MTD. So `MTD*2.0` passes whenever it's within the explored range.
- **327:** `best_p2 = max(p2_results, key=lambda x: x['P_success'])` — selection is pure modeled
  efficacy. Efficacy rises with dose, so the supra-MTD candidate (higher Cmax → higher
  `predict_efficacy`) wins (P_success 1.0 at 40 mg vs 0.84 at 20 mg).

Net: MTD = 20 mg → candidates {20, 10, 40} → 40 mg recommended. The design recommends a dose the
same run labeled overdosing. The MTD is the safety ceiling by definition; no efficacy gain may
override it.

## The fix (two parts — candidate cap + explicit selection guard)

**Part 1 — lines 304-305.** Candidates must be at or below the MTD. Replace:
```python
for dose_mg in [p2_base, p2_base*0.5, p2_base*2.0]:
    if dose_mg > max_dose * 1.1: continue
```
with:
```python
# Phase-2 candidates must NOT exceed the BOIN-identified MTD — the MTD is the
# safety ceiling, so a dose above it (previously p2_base*2.0) must never be a
# candidate however good its modeled efficacy. Explore the MTD and sub-MTD only.
for dose_mg in [p2_base, p2_base*0.75, p2_base*0.5]:
    if dose_mg > max_dose * 1.1: continue
    if p2_base and dose_mg > p2_base: continue   # never above the MTD
```

**Part 2 — lines 327-328.** Make the safety constraint explicit at selection too, so it survives
any future change to the candidate list. Replace:
```python
best_p2 = max(p2_results, key=lambda x: x['P_success']) if p2_results else {}
recommended_p2_dose = best_p2.get('dose_mg', p2_base)
```
with:
```python
# Select by efficacy ONLY among doses at or below the MTD. Candidates are already
# capped to <= MTD above; this guard makes the ceiling explicit and defends the
# invariant even if the candidate list changes later. Among safe doses pick the
# best modeled P_success.
_safe_p2 = [r for r in p2_results if (not p2_base) or r['dose_mg'] <= p2_base]
best_p2 = max(_safe_p2, key=lambda x: x['P_success']) if _safe_p2 else {}
recommended_p2_dose = best_p2.get('dose_mg', p2_base)
```

(The `no_safe_dose` branch at 353-354 is unchanged — when every level exceeds the DLT target the
run already refuses to recommend, which is correct.)

## Expected before → after (run c93845cd, MTD = 20 mg)
| field | before (bug) | after (fix) |
|---|---|---|
| Phase-2 candidates | {10, 20, **40**} | {10, 15, 20} |
| `recommended_Phase2_dose` | **"40 mg QD"** (2× MTD) | **"20 mg QD"** (= MTD) |
| recommended ≤ `true_MTD_dose_mg` (20) | **violated** | **holds** |

20 mg had P_success 0.84 — still a viable Phase-2 dose, now chosen because it's the best efficacy
at or below the MTD.

## Secondary (separate, lower priority)
The clinical run's `qc_events` carries a **`FASTP`** gate label — a sequencing-QC gate mapped onto
a clinical-simulation domain (wrong gate taxonomy). Not a safety bug, but it mislabels the QC
audit. Track separately; locate the gate-label mapping for `clinical_trial_simulation` and give it
a clinical-appropriate gate id (e.g. the `boin_dlt_boundary` gate already defined at lines 364-378).

## Verification (human, after applying)
Re-run `clinical_trial_simulation` on the same inputs as `c93845cd`. Confirm
`recommended_Phase2_dose` ≤ `operating_characteristics.true_MTD_dose_mg`, that the recommended
dose equals the best-efficacy dose at or below the MTD (20 mg here), and that the `no_safe_dose`
path still fires when all levels exceed the DLT target.
