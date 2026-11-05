# New `.nf` workflow safety/correctness — review patches (audit sweep, surface 1)

**Not applied.** Production `.nf` embedded Python (executed by Nextflow); a human applies +
live-verifies. Four NEW safety/correctness bugs from the 2026-11-05 audit (the BOIN dose>MTD and
ADMET DILI bugs have their own docs — `20261105_BOIN_PHASE2_DOSE_FIX_PATCH.md`,
`20261105_ADMET_DILI_FIX_PATCH.md` — not repeated here). Lines verified against current HEAD.

## 1. `repeated_dose_tox_prediction` reports PASS when the safety margin is 0 or missing — patient-safety
File: `pharmacology/repeated_dose_tox_prediction/main.nf:187`.
```python
'recommendation': 'PASS' if (safety_margin or 999)>=10 else 'FAIL_safety_concern'
```
`(safety_margin or 999)` is the classic `(x or default)` trap where `0` is a valid, dangerous
value: a margin that rounds to `0.0` is falsy → `0.0 or 999 → 999 ≥ 10 → PASS`; and when no
projected Cmax is supplied `safety_margin` is `None` → `None or 999 → PASS`. A near-zero margin and
a "no exposure data" case are both reported as a safety PASS (under-flagging — the dangerous
direction).
**Fix:**
```python
'recommendation': ('PASS' if (safety_margin is not None and safety_margin >= 10)
                   else ('FAIL_safety_concern' if safety_margin is not None else 'NOT_ASSESSED'))
```
Never use `or` to supply a numeric default where 0 is meaningful. Verify: a compound with
`safety_margin` 0.0 → FAIL; absent Cmax → NOT_ASSESSED (not PASS).

## 2. `phase2_dose_justification` recommends the HIGHEST dose when none is safe; unknown margin = "safe" — patient-safety
File: `pharmacology/phase2_dose_justification/main.nf:396,401`.
```python
is_safe = (safety_margin is None) or (safety_margin >= 3.0)   # 396 — unknown treated as SAFE
...
primary_dose = recommended_doses[0] if recommended_doses else candidate_doses[-1]   # 401 — highest fallback
```
`candidate_doses` is ascending (default `50,100,200`). When no dose is both efficacious and
≥3× margin, `recommended_doses` is empty → `candidate_doses[-1]` = the **highest** (most toxic)
candidate becomes the recommendation, and it flows into the FDA dose-justification narrative.
Also any dose with unknown margin (`None`) is declared safe.
**Fix:**
```python
is_safe = (safety_margin is not None) and (safety_margin >= 3.0)   # unknown = NOT safe
...
if recommended_doses:
    primary_dose = recommended_doses[0]                 # lowest efficacious + safe
else:
    primary_dose = None                                 # explicit "no acceptable dose — do not advance"
    # emit a clear no-safe-dose status downstream instead of a numeric recommendation
```
Mirror `clinical_trial_simulation`'s `no_safe_dose` path. Verify: a narrow-window input with no
≥3× dose produces a "do not advance" status, not the 200 mg row.

## 3. `docking_autodock_vina` reports success + a fabricated affinity vs a fake 1-alanine receptor — data-integrity
File: `pharmacology/docking_autodock_vina/main.nf:305-317` (ALA fallback) vs `:438-513` (status/gate).
When `receptor_pdb` is empty the code writes a single-alanine placeholder PDB ("minimal ALA receptor
for scoring only"), docks the ligand against it, and emits `success = success and bool(results_list)`
→ True with a numeric `best_affinity_kcal_mol` and a `docking_binding_score` gate — directly
contradicting the `:468-470` comment claiming "status='not_computed' … without fabricating a
verdict" (the `not_computed` branch at `:511-513` is unreachable because the ALA path always yields
a `best_score`). The affinity is physically meaningless (bound to one alanine).
**Fix:** on the no-receptor path set `success=False` / `status='not_computed'` and null
`best_score_kcal_mol` so the gate contract at `:468-470` holds; keep the ALA receptor only behind an
explicit `params.smoke_test` flag. Verify: docking with no receptor → `success=False`,
`status='not_computed'`, no numeric affinity, gate not evaluated.

## 4. `analyze_accelerated_stability…` "most stable formulation" is always the first-listed — scientific-correctness
File: `pharmacology/analyze_accelerated_stability_of_pharmaceutical_formulations/main.nf:135-152,227-237`.
`chemical_stability = 100*exp(-0.001*effective_time)` where `effective_time = time*accel_factor*
humidity_factor` — every term depends only on storage condition + time, **nothing on the
formulation**. So `avg_chem_stability` is identical across formulations; the selection
`if avg_chem_stability > best_stability:` (strict `>`, seeded 0) only fires for the first, so
`best_formulation` is whichever name is listed first, presented with a precise but meaningless
number.
**Fix:** make the degradation rate constant formulation-dependent (a per-formulation `k` from
excipients / pH / the solid-vs-liquid property already computed for `particle_size_change`), or stop
emitting a "most stable formulation" ranking the model cannot support. Verify: reordering the input
formulations must not change the winner; identical formulations must tie explicitly, not silently
pick the first.

## 5. ADMET per-compound DILI = panel-worst (provenance) — scientific-correctness (ties to the DILI patch)
`predict_admet_properties/main.nf` writes the panel-WORST DILI into every per-compound row
(`dili_aggregation:'worst_compound_in_panel'`), so per-compound values are overstated (e.g. aspirin
shows 0.675 because the panel worst was copied into each row). The deterministic parser + findings
descriptor then faithfully report the overstated per-compound DILI (they cannot distinguish a true
per-compound 0.675 from a propagated panel-worst). **Fix in the `.nf`:** carry the real
per-compound DILI probability per row and reserve the worst-of-panel only for a clearly-labeled
aggregate field; the QC DILI gate should read per-compound provenance, not the worst-of-set (see the
DILI patch doc). Verify: a 2-compound panel (one high, one low DILI) must show distinct per-compound
values, not two copies of the worst.
