# Roadmap-Tier Case Studies (Not Yet Executable as Full Reports)

These use cases are **real and strategically important but not yet backed by executed benchmark results**, so they are drafted here as compact briefs — problem, planned approach, target metrics, and the specific work needed — rather than as full Scientific reports that would be mostly `[GAP]`. They belong in the white paper's **"where we're going" / roadmap** narrative, not the evidence anchors. Once executed, each graduates to a full report pair.

Status legend: **IN-PROGRESS** (framework built, pivotal result pending) · **PLANNED** (protocol defined, not run) · **POSITIONING** (third-party evidence) · **NEGATIVE** (executed, honest null result).

---

## C1 — Multi-Omics Systems-Biology Integration (PLANNED)

- **Problem.** No platform reconciles the 6 immune-cell deconvolution methods, or the 4 single-cell multimodal integration methods, that disagree by ~30% on the same data.
- **Planned approach.** Consensus ensembles chained in one BioMate workflow, scored against public gold standards.
- **Gold standards & targets.** Sturm 2019 flow-validated PBMC (target Spearman ρ ≥ 0.85; best single method 0.87); NeurIPS 2021 CITE-seq/Multiome (scIB metrics, ARI ≥ 0.93); BEELINE GRN (AUPRC ≥ 0.50); NeurIPS 2023 perturbation (Pearson r ≥ 0.30).
- **Work needed.** Stage the datasets; execute the chains; report concordance vs gold standard. **Not executed.**
- **Source.** `docs/20260712_MULTIOMICS_SYSTEMSBIO_SHOWCASE_GOLD_STANDARDS.md`

## C2 — Autoimmune Cross-Specialty Chaining (SLE / RA / COVID) (PLANNED / ROUTING-ONLY)

- **Problem.** Autoimmune drug programs fail Phase 2→3 largely from poor patient stratification; the analysis spans GWAS → scRNA → spatial → GRN → ADMET → PBPK → trial design.
- **Status.** SLE Banchereau pilot (GSE65391, 158 SLE + 20 controls) has pass criteria defined (κ ≥ 0.5, FDR < 0.05, r ≥ 0.40) but is **not executed**. The virtual-cell/spatial/cyclic-peptide benchmark (RA/COVID, UC1–6) reached `workflow_ready` but ran only on **synthetic local data** (gold scores 0.05–0.45).
- **Work needed.** Load real datasets (GSE65391, GSE243885 Visium, NeurIPS CITE-seq); containerize missing tools (MEFISTO, CyclicMPNN, AlphaFold3, Space Ranger); execute and score.
- **Sources.** `docs/20260706_SLE_BANCHEREAU_PILOT_ELABORATION.md`, `docs/20260714_MULTIOMICS_VIRTUAL_CELL_SPATIAL_CYCLICPEPTIDE_BENCHMARK.md`

## C3 — CryoEnsemble: Rare-Conformer Recovery (IN-PROGRESS)

- **Problem.** Standard cryo-EM averages away conformational heterogeneity; existing methods (BME, cryoDRGN) can't recover states below ~5% population.
- **What works.** On synthetic ADK open/closed data at realistic SNR, the EM-mixture machinery recovers a 5% rare state **exactly** (95%/5%) where BME and cryoDRGN reach 0%.
- **Pivotal open item.** The neural-score diffusion-posterior-sampling run (H1d) is **not yet executed** — the framework's central novelty stands or falls on it. Real-data (EMPIAR-10059) posterior currently degenerates (forward-model normalization / pose-convention issues).
- **Work needed.** Run H1d; fix real-data calibration (~2 wk); benchmark vs 3DFlex/DynaMight.
- **Source.** `research_repos/cryoensemble_paper/`

## C4 — Proteomics QC Governance (PLANNED)

- **Problem.** Silent LC-MS/MS failures (failed pulldowns, bad enrichment, SMILES errors) cost $50–250K per wasted validation batch.
- **Planned approach.** mzQC (HUPO-PSI) with GOLD/SILVER/BRONZE tiers + protocol-aware profiles + SMILES QC gate.
- **Targets.** ≥95% expert-decision match; ≥80% analyst-time saving; <5% false-positive; ~15% SMILES-error detection (Whitehead 2022).
- **Work needed.** Build core QC layer (~9 days: parsers, thresholds, profiles); run PRIDE benchmarks (PXD000001/003452/010154). **Not built.**
- **Source.** `research_repos/biomate_proteomics_paper/20260225_1138_EVALUATION_PROTOCOL.md`

## C5 — Cross-Run Stability / Reproducibility (PLANNED)

- **Problem.** Clinical/regulatory use requires deterministic results; a multi-agent system must prove run-to-run concordance.
- **Planned approach.** Execute 5 representative workflows 10× each on identical inputs; measure concordance (target ≥90%; ρ ≥ 0.995).
- **Work needed.** Build the reproducibility harness + metrics DB; run. **Not executed.**
- **Source.** to create — `research_repos/biomate_stability_benchmark/`

## D1 — Automated Tool/DB Auto-Update (EXECUTED — HONEST NEGATIVE)

- **Result.** Discovery works (264 repos surfaced in 25 min; container naming fixed 8/16 → 15/15), but **wrapper generation fails: 0/14 tools reach workflow-ready**, 11/14 blocked by missing/dummy parameters. This is a real, measured **null result** on the hard part.
- **How to present.** Not a "BioMate wins" case study. Use as a **research-capability sidebar**: "automated discovery is tractable; parameter-schema inference from documentation is the open problem we're working on." Honest negatives strengthen credibility — but keep them out of customer-facing win briefs.
- **Source.** `research_repos/biomate_autoupdate_paper/manuscript/MANUSCRIPT_DRAFT.md`

## D2 — SGI-Bench Positioning (THIRD-PARTY, POSITIONING)

- **Evidence.** Independent Shanghai AI Lab benchmark: the best autonomous AI scores **33.83/100** across 1,000+ science tasks; code runs (>90%) but is correct only ~37% of the time.
- **How to present.** This is **not a BioMate benchmark** (BioMate is not scored on the same tasks). Use it in the white-paper **narrative** to justify the orchestration-over-autonomous-codegen thesis — paired with the BioMate agentic-evaluation case study (which *is* measured). Do not present it as a BioMate result.
- **Source.** `research/benchmark_evaluation/sgi_bench_analysis_for_biomate.md` (arXiv:2512.16969)

---

## Graduation checklist (Roadmap-tier → full report pair)

A use case becomes a full Scientific + Commercial pair when it can fill **both** §4.1 (real manual-vs-BioMate comparison) **and** §4.2 (real accuracy vs a reference). Priority order by ROI:
1. **C4 Proteomics QC** and **C5 Stability** — smallest lift (build + run a defined protocol).
2. **C3 CryoEnsemble H1d** — one pivotal run away from a genuine methods result.
3. **C2 Autoimmune / C1 Multi-omics** — highest strategic value, largest data/tooling lift.
