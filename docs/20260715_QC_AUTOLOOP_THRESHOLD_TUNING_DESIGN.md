# QC Auto-Loop: Intelligent Threshold Tuning Design

**Date:** 2026-07-15
**Context:** Design review of auto-loop parameter remediation after QC gate failures.
**Status:** Decision recorded — short-term path agreed, calibration deferred to accumulated data + manual fallback.

---

## 1. The Problem with Current Tuning

When a QC gate fails (e.g. hERG IC50 = 3 µM, below the 10 µM safety threshold), the auto-loop
suggests a new `logP_max` for the next run. The current logic in
`backend/experiments/admet_autoloop/param_tuner.py`:

```python
new_logp = max(MIN_LOGP, round(p.logp_max - 0.5, 1))   # always −0.5, regardless of gap
```

Three structural problems:

1. **Fixed blind step** — always −0.5 regardless of how far below threshold the metric is.
   If IC50 = 2 µM vs threshold 10 µM (5× gap), a single −0.5 logP step recovers only ~41%.
   Five iterations needed for what should be one.

2. **Per-gate independent handling** — when hERG and DILI both fail, each gate writes its own
   logP bound, potentially overwriting the other. Neither gate's bound is computed as the
   minimum safe value across all failing gates simultaneously.

3. **No target margin** — the step aims to just clear the threshold (10 µM), not to land
   safely above it. A compound landing at exactly 10 µM will fail again on any noise or
   run-to-run variation.

---

## 2. What `logP_max` Actually Is

`logP_max` is a **library filter**, not a compound property. It controls which batch of
compounds enters the screen:

```
logP_max = 5.0  →  screen compounds with logP 0–5  →  observe mean hERG IC50 = 3 µM
logP_max = 4.0  →  screen compounds with logP 0–4  →  observe mean hERG IC50 = ?
```

Changing `logP_max` does not modify any molecule's structure. It changes **which population
of compounds** is tested. Compounds with lower logP tend to have weaker hERG channel binding
(higher IC50 = safer), so tightening the filter shifts the screened population toward safer
compounds.

**This is a population-level problem, not a compound-level problem.**

The question the tuner needs to answer is:

> "If I set logP_max = X, what is the expected mean hERG IC50 of the compounds that will
> pass through that filter?"

A per-compound QSAR model (which BioMate has in `herg_cardiac_safety_qsar/main.nf`) answers
a different question: "for *this specific compound* with these properties, what is its IC50?"
That is useful for screening and ranking, but not directly for setting a population filter.

---

## 3. Domain Knowledge Audit

### What we have (and its limitations)

| Source | What it says | Limitation |
|---|---|---|
| Waring & Johnstone 2007 | ~2× IC50 per 1 logD unit reduction (population regression, AZ dataset) | logD not logP; AZ compound library, not BioMate's |
| Aronov 2008 (review) | `log10(IC50) ≈ 1.4 − 0.30 × logP` cited in code comment | Review paper; intercept 1.4 has no primary citation; coefficients not verified |
| BioMate QSAR (`herg_cardiac_safety_qsar`) | `log_ic50 = −1.2 − 0.35×logP − 1.0×cationic_flag + 0.003×mw ...` | Per-compound, not filter-level; disconnected from param_tuner |
| Lammert 2010 (DILI) | logP>4 AND MW>400 → elevated DILI risk | Categorical, not continuous; no probability model to invert |
| Kazius 2005 (Ames) | 29 structural alerts cover ~89% of Ames+ compounds | Alert-based, not logP-related; already encoded correctly |

### The core gap

We have directional knowledge (lower logP → higher IC50) and a slope estimate (~0.30–0.35 per
logP unit in log space). What we lack is a **calibrated population curve** for BioMate
specifically:

```
logP_max  →  mean hERG IC50 of screened compounds
```

This curve depends on:
- The specific compound library BioMate screens from
- Which ADMET predictor is running (DeepPurpose vs RDKit heuristics — the latter is active
  in the current environment per `predict_admet_properties_results.json`)
- The logP distribution of that library (which compounds cluster where)

No external paper can give this. It has to come from BioMate's own run history.

### Compound-class gap

The forum knowledge (`forum_knowledge.py`) notes explicitly:
> *"For non-basic compounds, ring rigidification or removal of planar aromatic systems is more
> effective. Filter tightening on logP works best for basic scaffolds."*

The current param_tuner applies the same logP rule to all compound classes. For non-basic,
non-lipophilic compounds failing hERG, logP reduction is the wrong lever — the gate should
flag this and route to manual review instead.

---

## 4. Improvement Plan

### Tier 1 — Algorithmic fixes (no new knowledge required)

**Gap-proportional step sizing**

Replace fixed −0.5 with a step proportional to the distance from threshold:

```python
gap_ratio = gate_result.threshold / gate_result.value   # e.g. 10/3 = 3.3× below threshold
logp_reduction = BASE_STEP * math.log10(gap_ratio)      # ~0.5 * 0.52 = 0.76 for 3.3× gap
new_logp = max(MIN_LOGP, round(p.logp_max - logp_reduction, 1))
```

At 3.3× below threshold → reduce logP by ~0.76 instead of 0.5.
At barely failing (1.05× below) → reduce by ~0.10 instead of 0.5.

**Target margin**

Aim for `threshold × SAFETY_MARGIN` (default 1.5×) rather than exactly the threshold:

```python
TARGET_MARGIN = 1.5   # target IC50 = 15 µM when threshold = 10 µM
effective_gap = (gate_result.threshold * TARGET_MARGIN) / gate_result.value
```

**Joint constraint resolution**

Collect logP bounds from ALL failing gates before writing any change:

```python
logp_bounds = []
for gate in failing_gates:
    logp_bounds.append(compute_logp_bound(gate, params))
new_logp = max(MIN_LOGP, min(logp_bounds))   # satisfies all gates simultaneously
```

Currently hERG and DILI write independently, with DILI potentially overwriting hERG's bound.

### Tier 2 — Knowledge improvements (short sessions, high ROI)

**Read Waring & Johnstone (2007) directly**

The knowledge_base.py entry paraphrases "roughly 2-fold per unit logP reduction." The actual
paper has regression coefficients with confidence intervals. Encode:
- Fitted slope (with CI) as a constant, not a comment
- Note that the paper uses logD not logP, and the correction for basic amines
- Restrict the rule to basic-amine scaffolds where it is validated

**Add compound-class branch**

Require `toxicity_report.json` to emit `scaffold_class` or `basic_amine_fraction`. Then:
- Basic amines → logP reduction (current path, now properly attributed)
- Non-basic scaffolds → emit advisory: *"logP reduction may not resolve this; structural
  modification or scaffold change required"* and route to manual review

### Tier 3 — BioMate-specific calibration (accumulate over time)

After each ADMET run, log:

```
{
  "run_id": ...,
  "logp_max_used": 5.0,
  "observed_mean_herg_ic50_uM": 3.2,
  "observed_min_herg_ic50_uM": 1.1,
  "n_compounds_screened": 50,
  "compound_class": "mixed"   # or "basic_amine" if classifiable
}
```

After 30+ runs, fit:

```
log10(mean_IC50) ~ a + b × logP_max
```

This is the population-level curve for BioMate's specific compound library and predictor.
Once fitted, the tuner can invert it analytically:

```python
# target: mean IC50 = threshold × SAFETY_MARGIN
target_log_ic50 = math.log10(threshold * SAFETY_MARGIN)
target_logp_max = (target_log_ic50 - intercept) / slope
```

This replaces all heuristics with a data-driven, BioMate-specific model. It also becomes
a proprietary asset — calibrated to exactly what BioMate runs, not to a 2007 AZ dataset.

---

## 5. Where Auto-Decision Fails → Ask the User

Some situations cannot be auto-resolved with current knowledge. Presenting pre-computed
options in these cases is false confidence in a different form — it implies we know the
solution space, which is exactly what we said we don't know.

The correct pattern: explain why the system cannot decide, then expose the parameter input
directly and let the user set it. The user is the domain expert.

| Situation | Why auto-decision fails | What to show |
|---|---|---|
| Non-basic scaffold failing hERG | logP reduction is the wrong lever for non-basic compounds | "hERG failure on a non-basic scaffold is not addressable by logP filtering. Set `logP_max` manually, or flag for structural review." → editable `logP_max` field |
| DILI fails with logP already ≤ 4.0 and MW ≤ 400 | Already at Lammert boundary; residual risk is structural, not physicochemical | "DILI flag persists below the Lammert boundary — likely a structural alert (e.g. Michael acceptor). logP reduction will not help. Set parameters manually." → editable fields |
| Conflicting gate constraints | All gates cannot be satisfied by any single logP_max | "hERG and DILI require incompatible logP bounds. No automatic resolution. Set `logP_max` manually." → editable field |
| No calibration data yet | No population curve; heuristic only | Apply Tier 1 gap-proportional heuristic and show uncertainty: "Suggested logP_max = X (heuristic, no run history yet). Override if needed." → editable field pre-filled with heuristic |

**Manual input contract:** When the auto-loop cannot decide, it must:
1. Say clearly why it cannot decide (one sentence, no hedging)
2. Expose the relevant parameter as an editable input field
3. Log whatever the user sets as a labeled data point for future calibration

The pre-fill from the heuristic is a starting point, not a recommendation — the user should
feel free to ignore it. A wrong auto-suggestion wastes an AWS Batch run; an editable field
costs the user 10 seconds.

---

## 6. Confidence-Based Auto-Loop Plan

Each gate's auto-loop confidence is assessed separately for the threshold (when to flag)
and the remediation (what to do about it). Only gates where both are supported get
fully automated remediation. Others fall back to manual input.

### Gates with full auto-loop confidence

| Gate | Threshold basis | Remediation basis | Action |
|---|---|---|---|
| **Ames** | Kazius 2005 structural alerts (GOLD) | Same paper — alerts ARE the mechanism; removing matching compounds directly fixes the flag | `ames_strict=True` auto-applied |
| **DILI** | Lammert boundary logP>4 AND MW>400 (SILVER but categorical) | Categorical: move filter below the known risk zone line | `logP_max=4.0, mw_max_da=400` auto-applied |
| **CYP-DDI R1/R2** | FDA 2020 guidance verbatim (GOLD) | FDA guidance prescribes the next step (clinical DDI study / TDI assay) — not a param change | Regulatory instruction emitted; no param change |
| **hERG (with QSAR output)** | Redfern/Bowes 10 µM (GOLD-metric) | BioMate's own QSAR model (coeff −0.35/logP unit) — invertible exactly if failing compound's descriptors are available | Analytical inversion of BioMate QSAR |

### Gates that fall back to manual input

| Gate | Why | What to show |
|---|---|---|
| **hERG (no compound descriptors)** | Can't invert QSAR without knowing failing compound's cationic_flag, MW, rings, HBD | Gap-proportional heuristic as pre-fill; user overrides |
| **PBPK Kp adjustment** | 25% Kp reduction is operational heuristic, no evidence basis for the magnitude | Expose Kp_scale as editable field with explanation |
| **Non-basic scaffold failing hERG** | logP reduction is the wrong lever | Flag that filter change won't help; ask user what to do |

### Why this works for Ames and DILI

Ames and DILI remediations are confident because the action is **categorical**, not
continuous. There is no step-size problem:

- Ames: either structural alerts are enabled or they aren't. Enabling them removes ~89%
  of Ames+ compounds (Kazius 2005). One switch, known effect, paper-backed.
- DILI: the Lammert boundary is a line. If you're above it, move below it. logP=4.0 and
  MW=400 are the target values. Not "reduce by some amount" — "set to these values."

This is why they can be auto-looped without a population curve. The uncertainty in hERG
comes from needing a *step size* across a continuous parameter — Ames and DILI don't have
that problem.

### Why hERG needs BioMate's own QSAR model

External regression data (Waring & Johnstone 2007, Aronov 2008) cannot be reliably used
because:
- Waring & Johnstone used logD (not logP) on an AstraZeneca compound set from 2007
- The intercept (1.4) has no verified primary source
- Population-level regression applies to the compound set used in that study, not BioMate's

BioMate already has its own QSAR model (`herg_cardiac_safety_qsar/main.nf`, line 117):

```python
log_ic50 = -1.2 - 0.35*logP - 1.0*cationic_flag + 0.003*mw - 0.15*ring_count + 0.4*hbd
```

If the failing compound's descriptors are available from the QSAR output (`herg_risk.json`
already emits logP, MW, estimated pKa per compound), the inversion is exact:

```python
target_ic50 = threshold * SAFETY_MARGIN          # e.g. 10 µM * 1.5 = 15 µM
other = -1.0*cationic_flag + 0.003*mw - 0.15*rings + 0.4*hbd
target_logP = (-1.2 + other - log10(target_ic50)) / 0.35
new_logP_max = max(MIN_LOGP, round(target_logP, 1))
```

No external paper needed. The model we control is the source of truth.

## 7. Implementation Sequence

Ordered by confidence and impact — highest-confidence changes first.

| # | Change | File(s) | What it unlocks |
|---|---|---|---|
| 1 | **Ames**: make `ames_strict=True` auto-apply on HALT, not suggest | `admet_autoloop/param_tuner.py` | First fully-confident auto-loop action |
| 2 | **DILI**: make logP=4.0/MW=400 auto-apply as categorical set, not step | `admet_autoloop/param_tuner.py` | Second fully-confident auto-loop action |
| 3 | **hERG**: gap-proportional step + target margin as interim heuristic | `admet_autoloop/param_tuner.py` | Smarter than blind −0.5 while QSAR wiring is pending |
| 4 | **hERG**: joint constraint — collect all gate logP bounds before writing | `admet_autoloop/param_tuner.py` | Prevents hERG and DILI bounds overwriting each other |
| 5 | **hERG**: read failing compound descriptors from QSAR output → invert BioMate model | `autoloop_bridge.py` + `param_tuner.py` | Makes hERG recommendation fully confident |
| 6 | **All gates**: manual input path — expose editable field when auto-decision fails | `auto-loop-panel.tsx` | Correct UX for uncertain cases |
| 7 | **Calibration logging**: log (logP_max, observed mean IC50) per run | `autoloop_bridge.py` + `calibration_store.py` | Foundation for future population curve |
