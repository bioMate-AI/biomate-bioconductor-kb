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

## UC-3 — Transcriptomics: bulk RNA-seq differential expression (DESeq2)
**Workflow:** `subworkflows/bioconductor/deseq2/main.nf` (container
`bioc-domain-transcriptomics:3.20-slim`, CPU). **Input:** a simulated 12-sample (6 control / 6
treated) × 2000-gene integer count matrix (`cts.csv`) + sample metadata (`coldata.csv`, a `condition`
column), with **100 planted DE genes** (50 up 3×, 50 down ⅓×). **Run
`b8cd8747-6527-4f80-b1ec-8b2d2ad62e3b`** — succeeded on CPU Batch.

**Result — statistically honest (not upper-bound):**
- 2000 genes → 1720 after low-count filtering; **80 called DE at padj<0.05**.
- **Planted-DE recovery: 77/100** at padj<0.05, **direction 77/77 correct** (every recovered gene has
  the right up/down sign). Top hits are planted up genes (e.g. GENE0019 log2FC 1.61, padj 4.7e-273).
- **False positives: 3/1620 non-planted → empirical FDR ≈ 0.037**, right at the BH padj<0.05 control.
- Emitted `qc_metrics.json` (process `BIOC_DESEQ2_STANDARD_DE_FROM_MATRIX`, the Bioconductor QC-harness
  gates: diagnostic MA/PCA, low-count filtering).

The 77% recall (not 100%) is the honest outcome — low-fold / low-expression planted genes don't reach
significance at n=6/group — and the FDR lands on the nominal 5%. A third independent domain
(transcriptomics) validated end-to-end, with a proper statistical result rather than a near-perfect
simulation artifact.

**Gotcha (recorded for reuse):** bioconductor subworkflows with a `// Input: a, b` header read their
inputs by **named params** (`params["cts"]`, `params["coldata"]`), staged under those basenames — NOT
the `omics` list used by the collect-all multi-omics shape (SNF). Passing `omics` here failed with
`Required input file for cts not found`; passing `cts`/`coldata` params fixed it. (Executor logic:
`nextflow_executor.py` Style-A bioc entry wrapper, ~line 2235.)

---

### Method notes / honesty
- `qc_profile=admet_standard` was used deliberately: the default `cipa` profile can suppress the
  ADMET hERG gate (per prior sessions). With `admet_standard` the hERG/DILI gates evaluate.
- Inputs here are known reference drugs, not a novel screening library — this validates the pipeline
  and that it reproduces a textbook liability (terfenadine/hERG), not de-novo discovery.
- Cost/footprint per use case is small (CPU, ≈$0.008/run) — the same executor path a real screen uses.
