# Death-Zone Workflows — Audit & Fix Plan
**Date:** 2026-04-28  
**Workflows audited:** phase2_dose_justification, biomarker_patient_enrichment,
polymorph_stability_screening, pbpk_disease_state

---

## Overall Assessment

All 4 workflows have **correct underlying math** but share a structural problem:
they assume clean, pre-formatted JSON inputs that don't exist naturally in the
pipeline. They are missing the wiring that connects them to upstream workflow
outputs. Two have scientific completeness gaps that make them not production-ready.

---

## 1. `phase2_dose_justification`

**Status: Structurally weak — reporting layer only**

**What works:**
- Emax/sigmoid Hill math is correct
- EC10/EC90 inversion formula correct
- Safety margin ratio (AUC_MTD / AUC_efficacious) correct
- FDA 2023 E-R guidance 4-section narrative structure correct

**Critical gaps:**

1. **Depends on upstream output that doesn't exist as clean JSON.**  
   Takes `er_params_json` with `{ec50_uM, emax_pct, hill, r_squared}` — but these
   come from a fitted nlmixr2/NONMEM PopPK model run on actual clinical data.
   A user cannot construct this manually from a first-in-human trial. This workflow
   is a **reporting layer**, not a modeling tool.

2. **Dose-to-exposure conversion is missing.**  
   The workflow maps dose (mg) to effect (%) but skips the PK step entirely —
   it assumes AUC ∝ dose linearly. For drugs with nonlinear PK (saturable
   metabolism, autoinduction, food effect) this is wrong. The real path is:
   `dose → PopPK model → AUC distribution → E-R model → % responders`.

3. **PTS (probability of technical success) is a rough heuristic.**  
   The Lalonde 2007 3-component framework used (P1 × P2 × P3) is valid conceptually
   but the P2 component (therapeutic window → success probability) is ad hoc in
   this implementation. FDA does not accept PTS estimates from heuristic formulas;
   they accept model-based simulations.

**Fix required:**
- Wire to read `nlmixr2_population_pk` output JSON directly (auto-populate ec50, emax,
  hill from fitted model results)
- Add Monte Carlo dose→AUC→effect simulation using PopPK variability parameters
- Add a clear scope statement: "This tool summarizes E-R analysis results from a fitted
  PopPK/PD model. It requires prior completion of nlmixr2_population_pk."

---

## 2. `biomarker_patient_enrichment`

**Status: Statistically correct, scientifically incomplete**

**What works:**
- Logistic regression with OR and 95% CI: correct
- Benjamini-Hochberg FDR correction: correct
- Youden's J cut-point optimization: correct
- Enrichment ratio (ER), NNT, PEF, NNS formulas: correct
- Phase III sample size comparison using two-proportion z-test: correct

**Critical gaps:**

1. **No cross-validation for cut-point — optimistic bias.**  
   Finding the Youden cut-point on the same data used to discover the biomarker
   is circular. The reported sensitivity/specificity is optimistically biased;
   the true performance in an independent Phase III population will be worse.
   Requires bootstrap or k-fold CV for honest performance estimates.

2. **No randomized-trial structure.**  
   Real predictive biomarker analysis requires comparing biomarker+ vs biomarker-
   *within each treatment arm* of a randomized trial. This workflow assumes single-arm
   data (responders vs non-responders) — valid for single-arm Phase II but not for
   randomized designs where a prognostic biomarker (affects outcome regardless of
   treatment) can be confused with a predictive biomarker (affects response to
   *this specific treatment*).

3. **Missing FDA regulatory warning.**  
   FDA's 2014 biomarker guidance requires biomarkers to be **pre-specified** before
   data lock. Post-hoc biomarker discovery from Phase II data is hypothesis-generating,
   not confirmatory. The workflow output must flag this: results need independent
   prospective validation before use in Phase III enrichment strategy.

**Fix required:**
- Add bootstrap loop (n=1000) for cut-point: report bias-corrected sensitivity/specificity
- Add `study_design` param ("single_arm" vs "randomized") with appropriate handling
- Add mandatory regulatory disclaimer to output narrative

---

## 3. `polymorph_stability_screening`

**Status: Useful risk flag, NOT a prediction — scope mislabeled**

**What works:**
- RDKit descriptor extraction (HBD, HBA, RotBonds, MW, LogP, PSA): correct
- Fleming 2010 / Blagden-Davey 2003 heuristic risk scoring: correct
- ICH Q1A/Q1B stability categories: correct
- Excipient compatibility alerts: correct
- ICH Q6A screening protocol recommendation: correct

**Critical gaps:**

1. **This is not crystal structure prediction.**  
   Real polymorph prediction requires:
   - Crystal structure prediction (CSP) engines: CSD Python API (licensed, CCDC),
     CrystalPredict, xtb/CREST for conformational sampling, GRACE/USPEX for lattice
     energy minimization
   - DFT or force-field lattice energy calculations
   - None of these are available in biomni-tools container

2. **RDKit not in biomni-tools image.**  
   The workflow assumes `from rdkit import Chem` but RDKit is not installed in the
   current biomni-tools container. Verified locally: `ModuleNotFoundError`.
   The workflow has a heuristic fallback that parses SMILES as a string — this
   fallback is crude and will give wrong HBD/HBA counts for complex molecules.

3. **Scope overstated in current output.**  
   The output JSON says "Polymorph Screening" which implies predictive capability.
   The correct framing is "Polymorph Risk Stratification" — it tells you whether
   to commission experimental screening, not whether polymorphs exist.

**Fix required:**
- Rename output field from "polymorph_screening" to "polymorph_risk_stratification"
- Add explicit scope statement to output: "This tool assesses molecular risk factors
  for polymorphism. It does NOT predict crystal structures or confirm polymorph
  existence. High-risk compounds require experimental XRPD/DSC screening."
- Add RDKit to biomni-tools Dockerfile, or add a more robust SMARTS-based fallback
  that correctly counts H-bond donors/acceptors

---

## 4. `pbpk_disease_state`

**Status: Most scientifically solid — one wiring gap, one approximation concern**

**What works:**
- GFR power-law CLr scaling `(GFR_patient/GFR_normal)^0.75` (Nolin 2010): correct,
  validated against FDA examples
- Well-stirred hepatic model with Child-Pugh hepatocyte/LBF fractions: correct
- High-extraction-ratio flow-limited branch: correct
- CONTRAINDICATED flag at AUC_ratio > 5: correct per FDA guidance
- FDA §8.6/§8.7 label language template: correct format

**Concerns:**

1. **Protein binding correction uses a generic approximation.**  
   The albumin-mediated binding correction:
   `fu_impaired = fu_normal / (1 + α(1 - albumin_ratio))`
   uses a fixed binding constant α. For highly protein-bound drugs (fu < 0.05),
   the true correction depends on drug-specific binding affinity (Ka) to albumin
   and α1-acid glycoprotein. The generic approximation can be off 2-3× for
   tight binders (warfarin, diazepam). Should warn when fu < 0.05.

2. **Takes manual PK parameters as input.**  
   `cl_renal_fraction`, `fu_plasma`, `vd_lkg` must be known in advance.
   In practice these come from in vitro assays (microsomal stability, plasma
   protein binding, Caco-2) — i.e., upstream ADMET workflow outputs.
   Users cannot construct these parameters without prior lab data.

**Fix required:**
- Add `fu_plasma < 0.05` warning about protein binding approximation uncertainty
- Wire to accept ADMET workflow output JSON directly (extract fu, logP, renal
  clearance fraction automatically)
- Update the wiring documentation to show the dependency chain:
  `ADMET → pbpk_disease_state` and `PBPK_simulation → pbpk_disease_state`

---

## Wiring Map (What Needs to Connect to What)

```
Existing upstream                    New downstream
─────────────────                    ──────────────
predict_admet_properties  ──────────→ pbpk_disease_state
  (fu_plasma, logP, clr_fraction)      (currently manual input)

pbpk_simulation           ──────────→ pbpk_disease_state
  (Vd, clearance params)               (currently manual input)

nlmixr2_population_pk     ──────────→ phase2_dose_justification
  (ec50, emax, hill, r2)               (currently manual input)

Phase II trial data        ──────────→ biomarker_patient_enrichment
  (patient_data CSV/JSON)              (external data, always manual)

predict_admet_properties  ──────────→ polymorph_stability_screening
  (SMILES already available)           (SMILES re-entered manually)
```

The polymorph and biomarker workflows need no structural wiring changes — just
ensure SMILES from the chat context is auto-populated for polymorph, and Phase II
data upload is the natural entry point for biomarker enrichment.

---

## Fix Priority

| # | Fix | Workflow | Effort | Risk |
|---|-----|----------|--------|------|
| P0 | Bootstrap CV for Youden cut-point | biomarker_enrichment | 2 days | Overfitting in Phase III if skipped |
| P0 | Regulatory pre-specification warning | biomarker_enrichment | 0.5 days | FDA compliance if skipped |
| P0 | Scope relabeling (risk stratification, not prediction) | polymorph | 0.5 days | Customer misuse if skipped |
| P0 | Add `fu < 0.05` warning | pbpk_disease_state | 0.5 days | Incorrect dose recommendations |
| P1 | Wire ADMET output → pbpk_disease_state input | pbpk_disease_state | 2 days | Friction only |
| P1 | Wire nlmixr2 output → phase2_dose_justification | phase2_dose_justification | 2 days | Friction only |
| P1 | Add Monte Carlo dose→AUC→effect simulation | phase2_dose_justification | 3 days | Scientific completeness |
| P2 | Add RDKit to biomni-tools container | polymorph | 1 day | Fallback works but is less accurate |
| P2 | Add randomized-trial arm structure | biomarker_enrichment | 3 days | Prognostic vs predictive confounding |

---

## UX (deferred to separate decision)

Chaining suggestions and parameter pre-fill from upstream outputs are the highest-value
UX additions. No new components needed — extensions to `ai_assistant.py` routing and
the existing `_inject_uploaded_files_into_params` pattern are sufficient.
See `docs/20260428_PHARMA_DEATH_ZONE_COVERAGE_AND_ROADMAP.md` for context.
