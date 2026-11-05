# BioMate use-case validation log (live on dev, CPU Batch)

A running log of flagship use cases exercised **end-to-end through BioMate's own executor** on AWS
CPU Batch, each with a real/representative input and a check of the scientific + QC output. Companion
to the generalization validation (`20261104_GENERALIZATION_SESSION_IMPLEMENTATION.md`) and the
multi-omics cohort study (`20261105_SYSUCC_SIM_MULTIOMICS_VALIDATION.md`). Append one section per use
case. All runs go through `POST /api/nextflow/execute`; nothing is computed off-platform.

---

## UC-1 — Multi-omics patient stratification (transcriptomics + proteomics + metabolomics/methylation)
Covered in full by `20261105_SYSUCC_SIM_MULTIOMICS_VALIDATION.md`: SNF integration (ARI 0.978 on a
150-patient 3-subtype cohort), data-driven QC gates emitted+evaluated live, cross-omics driver fusion
(24/24 drivers, permutation-significant; 0 false positives on null and weak-signal controls), and a
subtype-prediction model (5-fold CV acc 0.950). Runs `ab67ad23` (SNF), `27ba372e` (model), `9849fe21`
(weak-signal control).

## UC-2 — ADMET / drug-discovery toxicity screening
**Workflow:** `pharmacology/predict_admet_properties/main.nf` (container `biomni-admet:x86`, CPU).
**Input:** a SMILES list — aspirin (safe control), **terfenadine** (antihistamine withdrawn for hERG
cardiotoxicity), caffeine (safe). `qc_profile=admet_standard`.
**Run `a4fe422e-3e52-4ada-b11b-e78fa33e01cc`** — succeeded on CPU Batch (~155 s, ≈$0.0085).

**Result — scientifically correct, QC-gate-ready:**
- The `admet_ai` model ran (not just the RDKit fallback): per-compound `hERG_prob`, `DILI_prob`,
  `Caco2`, `BBB`, `HIA`, `PPBR` in `toxicity_report.json`.
- **Terfenadine → hERG IC50 0.0124 µM** (≪ the 10 µM ICH S7B safety line) — flagged as a strong hERG
  blocker, exactly the liability it was withdrawn from market for. Caffeine → 432 µM (safe).
- `qc_metrics.json` (process `PREDICT_ADMET_PROPERTIES`, domain pharmacology): `herg_ic50_uM=0.0124`,
  **`herg_safe_above_10uM=false`**, `dili_risk=high`, `admet_dili_probability_passes=false`,
  `ames_positive=false`; `evidence_tier = GOLD-Redfern2003 / SILVER-Kazius2005 / SILVER-Mulliner2016`.
  The hardcoded ADMET QC branch consumes this (hERG ≥10 µM GOLD gate), so the cohort's hERG
  cardiotoxicity liability is surfaced as a failing gate.

**What this adds beyond UC-1:** a second, independent domain (drug discovery) exercised end-to-end —
chemistry input (SMILES), a model-backed prediction (`admet_ai`), and the QC-gate path on toxicology
endpoints (hERG/DILI/Ames) rather than clustering quality. Note this uses the **pre-existing hardcoded
ADMET gate**, not the generalized declared-gate engine (UC-1); both QC paths are now live-verified.

---

### Method notes / honesty
- `qc_profile=admet_standard` was used deliberately: the default `cipa` profile can suppress the
  ADMET hERG gate (per prior sessions). With `admet_standard` the hERG/DILI gates evaluate.
- Inputs here are known reference drugs, not a novel screening library — this validates the pipeline
  and that it reproduces a textbook liability (terfenadine/hERG), not de-novo discovery.
- Cost/footprint per use case is small (CPU, ≈$0.008/run) — the same executor path a real screen uses.
