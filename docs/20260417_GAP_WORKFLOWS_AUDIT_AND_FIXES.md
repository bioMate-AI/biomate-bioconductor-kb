# Gap-Fill Workflows Audit — IDs 12877–12884
**Date:** 2026-04-17  
**Branch:** integration/next-phase

---

## Scope

Full audit of 8 newly built drug development Nextflow workflows (IDs 12877–12884).  
8 criteria × 8 workflows = 64 structural checks + full Python logic and scientific formula review.

**Result: 2 real issues fixed, 64/64 structural checks pass after fixes.**

---

## Audit Criteria

Same 8-item checklist from `docs/20260417_WORKFLOW_AUDIT_AND_FIXES.md`:

| # | Check | What it catches |
|---|-------|----------------|
| 1 | `main.nf` + `nextflow.config` both exist | Missing files |
| 2 | AWS container conditional present | Wrong/missing ECR image path |
| 3 | `python3 << 'PYEOF'` (quoted) | Unquoted `PYEOF` allows `$var` interpolation inside Python |
| 4 | Named `workflow NAME_WORKFLOW` block | Missing callable entry point |
| 5 | Bare `workflow { }` entry block | Cannot run standalone |
| 6 | `versions.yml` cat block | Missing Nextflow version tracking |
| 7 | No `${params.X}` inside PYEOF | Params must go through `export PARAM_*` env vars |
| 8 | `solve_ivp` → `sol.success` check | Silent NaN propagation on ODE failure |

---

## Bugs Found and Fixed

### Bug 1 — `adaptive_trial_design`: Thompson sampling division by zero

**File:** `drug_discovery/adaptive_trial_design/main.nf`

**Root cause:**  
In the Thompson sampling allocation function (`thompson_weights`), after computing per-arm
win probabilities raised to power `exponent`, the weights are normalised:

```python
probs  /= probs.sum()
```

In degenerate cases (all arms identical early in the trial, or `exponent` produces all-zero
floats due to numerical precision), `probs.sum()` can be zero, causing a `RuntimeWarning:
divide by zero encountered in true_divide` that produces NaN allocation weights. NaN
allocation fed to `np.random.multinomial` raises `ValueError`, crashing the simulation.

**Fix:**

```python
probs  /= (probs.sum() + 1e-10)
```

The epsilon guard is several orders of magnitude below any real probability, so it never
affects normal operation. Matches the standard defensive pattern for softmax-like
normalisation.

---

### Bug 2 — `pbpk_pediatric_pregnancy`: Dead import of `solve_ivp`

**File:** `pharmacology/pbpk_pediatric_pregnancy/main.nf`

**Root cause:**  
Line 67 imported `solve_ivp` from `scipy.integrate` — this is a leftover from an early
draft that used a full ODE system. The final implementation uses the closed-form
well-stirred hepatic clearance model and allometric Vd scaling, neither of which calls
`solve_ivp`. The dead import is harmless on biomni-tools (scipy is installed) but:

1. Misleads code readers into thinking ODE integration is used
2. Violates check 8 in spirit: if a future maintainer sees the import and adds an ODE
   call without a success check, this audit rule would be bypassed

**Fix:** Removed the unused import line.

---

## Non-Issues Investigated

### hERG safety margin formula direction
`safety_margin = ic50_uM / free_cmax` — higher margin = safer. This is the correct
convention per ICH E14 (safety margin of 30× is "minimal risk"). The formula was not
inverted. ✓

### Z-factor formula (HTS)
`Z = 1 - 3 * (sd_pos + sd_neg) / |µpos - µneg|` — matches Zhang et al. 1999. Division
by zero guarded with `if denom < 1e-10: return 0.0`. ✓

### Pediatric maturation Hill function
`F_mat = age^n / (TM50^n + age^n)` — correct Richards sigmoid, calibrated to
Bjorkman 2005 TM50/hill values. Age clamped to 0.003 yr minimum to prevent zero. ✓

### Antibody pI binary search convergence
100-iteration binary search over [0, 14]; charge at pH function is strictly monotone
decreasing, so bisection always converges. ✓

### E-R Hill inversion formula
For Emax target: `E = EC50 * (E_target / (Emax - E_target))^(1/hill)` — this is the
exact algebraic inverse of `E_target = Emax * E^n / (EC50^n + E^n)`. Guard for
`pct_target >= emax` and `ratio <= 0` present. ✓

### O'Brien-Fleming boundary
`z* = z_alpha / sqrt(t_frac)` — Lan-DeMets 1983 approximate OBF boundary. Valid for
group sequential analyses with equal information increments. ✓

### Bare `except:` patterns
Multiple workflows use `except: return default` in the `auto_convert` helper functions
and `except: pass` in SMILES/JSON parsers. These are intentional defensive patterns
at the parameter-parsing boundary (not inside scientific computation): if a user
supplies a non-numeric string for a numeric param, returning `None` triggers the default
value path rather than crashing. Scientific exceptions (ODE failures, fit failures) use
named `except Exception as exc:` with logging. No silent-failure risk in the
computation paths. ✓

---

## Final Check Results

```
ALL 8 WORKFLOWS PASS — 64 checks
```

| Workflow | 8/8 | Python logic | Science |
|----------|-----|-------------|---------|
| pharmacology/herg_cardiac_safety_qsar        | ✓ | ✓ | ✓ |
| pharmacology/genotoxicity_ames_prediction    | ✓ | ✓ | ✓ |
| drug_discovery/target_tractability_scorer    | ✓ | ✓ | ✓ |
| pharmacology/pbpk_pediatric_pregnancy        | ✓ | ✓ (dead import removed) | ✓ |
| pharmacology/antibody_developability         | ✓ | ✓ | ✓ |
| drug_discovery/hts_plate_qc_hit_calling      | ✓ | ✓ | ✓ |
| pharmacology/exposure_response_modelling     | ✓ | ✓ | ✓ |
| drug_discovery/adaptive_trial_design         | ✓ | ✓ (div/0 fixed) | ✓ |

---

## DB Sync

After fixes, `workflow_json` for IDs 12880 and 12884 re-synced to DB (full content, no
truncation). FTS index rebuilt. BGE embeddings unchanged (content changes do not affect
text-based embeddings; embeddings cover name + description + tags + annotation).
