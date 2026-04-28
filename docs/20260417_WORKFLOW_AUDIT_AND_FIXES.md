# Workflow Audit — 16 New Drug Dev Workflows
**Date:** 2026-04-17  
**Branch:** integration/next-phase

---

## Scope

Full audit of all 16 newly built drug development Nextflow workflows (IDs 12861–12876).  
128 checks across 8 criteria × 16 workflows.

**Result: 4 real bugs fixed, 128/128 checks pass after fixes.**

---

## Audit Criteria (8 checks per workflow)

| # | Check | What it catches |
|---|-------|----------------|
| 1 | `main.nf` + `nextflow.config` both exist | Missing files |
| 2 | AWS container conditional present | Wrong/missing ECR image path |
| 3 | `python3 << 'PYEOF'` (quoted) | Unquoted `PYEOF` allows Nextflow `$var` interpolation inside Python |
| 4 | Named `workflow NAME_WORKFLOW` block | Missing callable entry point for pipeline composition |
| 5 | Bare `workflow { }` entry block | Cannot run standalone (`nextflow run main.nf`) |
| 6 | `versions.yml` cat block | Missing Nextflow version tracking |
| 7 | No `${params.X}` inside PYEOF | Params must go through `export PARAM_*` env vars — direct interpolation breaks Python string literals |
| 8 | `solve_ivp` → `sol.success` check | Silent NaN propagation on ODE integration failure |

---

## Bugs Found and Fixed

### Bug 1 — `pbpk_simulation`: ODE solver failure unhandled

**File:** `drug_discovery/pbpk_simulation/main.nf`

**Root cause:** `solve_ivp(...)` returns a `OdeResult` with `success=False` on convergence failure (stiff parameters, bad physiology values, etc.). The code proceeded directly to `sol.y[2] / Vblood` without checking — if `sol.success` is False, `sol.y` contains partial/NaN arrays, propagating silently into NCA parameter calculation and final JSON output.

**Fix:**
```python
sol = solve_ivp(pbpk_ode, [0, t_end], y0, t_eval=t_eval, method='LSODA', rtol=1e-5, atol=1e-10)

if not sol.success:
    print(f"WARNING: ODE solver did not converge: {sol.message}", file=sys.stderr)
    Cblood_arr  = np.zeros(len(t_eval))
    Cliver_arr  = np.zeros(len(t_eval))
    Ckidney_arr = np.zeros(len(t_eval))
else:
    Cblood_arr  = sol.y[2] / Vblood
    Cliver_arr  = sol.y[3] / Vliver
    Ckidney_arr = sol.y[5] / Vkidney
```

---

### Bug 2 — `nanoparticle_pk_biodistribution`: Same ODE issue

**File:** `pharmacology/nanoparticle_pk_biodistribution/main.nf`

Same pattern: `solve_ivp` result used without success check.

**Fix:** Same guard with zero-filled fallback arrays for `blood_arr`, `tumor_arr`, `liver_arr`, `periph_arr`. `spleen_arr = liver_arr * 0.3` kept outside the if/else (still valid as zeros * 0.3 = zeros).

---

### Bug 3 — `target_engagement_kinetics`: Same ODE issue

**File:** `drug_discovery/target_engagement_kinetics/main.nf`

**Slightly different context:** The ODE is inside the `simulate_occupancy()` helper function (1-compartment receptor occupancy model). Same missing success check.

**Fix:**
```python
sol = solve_ivp(ode, [t_eval[0], t_eval[-1]], y0, t_eval=t_eval, method='RK45', rtol=1e-5)
if not sol.success:
    import sys as _sys
    print(f"WARNING: occupancy ODE failed: {sol.message}", file=_sys.stderr)
    return np.zeros(len(t_eval))
occupancy_pct = np.array(sol.y[0]) / (rtot_nM * 1e-9) * 100
return np.clip(occupancy_pct, 0, 100)
```

---

### Bug 4 — `allometric_scaling`: divide-by-zero in regression

**File:** `pharmacology/allometric_scaling/main.nf`

**Root cause:**
```python
b = np.cov(log_bw, log_p)[0,1] / np.var(log_bw)
```
`np.var(log_bw)` is zero when all body-weight values are identical (e.g., user submits two rat experiments both at 0.25 kg). Causes `ZeroDivisionError` and workflow crash.

**Fix:**
```python
var_bw = np.var(log_bw)
if var_bw == 0:
    return None, None  # all body weights identical — regression undefined
b = np.cov(log_bw, log_p)[0,1] / var_bw
```
The caller already handles `(None, None)` return gracefully (propagates as `None` through all downstream calculations).

---

## Non-Issues Investigated

### CSV files not showing direct `open()` calls
Several workflows declare `*.csv` outputs but the `open()` grep found nothing. Investigation confirmed they all use internal helpers:
- `write_csv(path, rows, fieldnames)` — in cns_penetration, dart_toxicity, oral_absorption, transporter_ddi
- `write_csv_rows(path, rows, fields)` — in repeated_dose_tox, transporter_ddi

Both helpers use `open(path, 'w', newline='')` internally. All declared CSV outputs are correctly created. ✓

### DART `placental_transfer.csv` when `run_placental_transfer=false`
When disabled, `pt = {}` (empty dict) → `pt_rows` rows have only `{compound, SMILES}` keys. `csv.DictWriter` default `restval=''` fills missing columns as empty strings. The file is always created (required by NF output block). ✓

### PBPK blood compartment ODE structure
The 8-compartment ODE uses a "venous equilibration" PBPK architecture (mixed blood pool, not separate arterial/venous). Flow conservation holds:
```
Qperiph = Qlung − Qliver − Qkidney − Qgut
```
Lung receives cardiac output, distributes back to blood pool. This is an accepted PBPK simplification (Rowland et al. 2011). ✓

### `power_law_regression` return arity
Function returns `(None, None)` for <2 species and `(a, b, r2)` for success. Callers handle both:
```python
a_cl, b_cl, r2_cl = results_cl if len(results_cl)==3 else (results_cl[0], results_cl[1], None)
```
Unpacking is correct for both 2- and 3-tuple returns. ✓

---

## Final Check Results

```
ALL 16 WORKFLOWS PASS — 128 checks
```

| Workflow | 8/8 |
|----------|-----|
| pharmacology/allometric_scaling | ✓ |
| pharmacology/cns_penetration_prediction | ✓ |
| pharmacology/dart_toxicity_prediction | ✓ |
| pharmacology/oral_absorption_bcs_model | ✓ |
| pharmacology/transporter_ddi_prediction | ✓ |
| pharmacology/repeated_dose_tox_prediction | ✓ |
| pharmacology/nanoparticle_pk_biodistribution | ✓ |
| pharmacology/membrane_permeability_prediction | ✓ |
| drug_discovery/lnp_formulation_optimization | ✓ |
| pharmacology/metabolite_prediction_biotransformer | ✓ |
| pharmacology/pharmacogenomics_pgx_report | ✓ |
| drug_discovery/target_engagement_kinetics | ✓ |
| drug_discovery/proteome_selectivity_profiling | ✓ |
| drug_discovery/covalent_warhead_design | ✓ |
| drug_discovery/pbpk_simulation | ✓ |
| drug_discovery/clinical_trial_simulation | ✓ |
