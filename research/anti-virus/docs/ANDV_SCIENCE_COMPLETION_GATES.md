# ANDV campaign — science completion gates

**Bar:** Each track must pass **in silico** science gates before manuscript claims. BioMate scope is **compute only** — no wet-lab work.

Last updated: 2026-06-07

---

## Plan A (vaccine / epitope) — strongest translational science

| Gate | Status | Evidence / blocker |
| --- | --- | --- |
| Full-GP MHCnuggets + MHCflurry on Q9E006 | **DONE** | `plan_a_epitope/PLAN_A_FULL_GP_*.tsv` |
| Strict dual-tool consensus (both binder=True) | **DONE** | **47** pairs → `PLAN_A_CONSENSUS_BINDERS.tsv` |
| Science tiers (consensus + GPC surface + conservation) | **DONE** | **4** tier A + **24** tier B → `PLAN_A_SCIENCE_TIERS.json` |
| IEDB population coverage | **DONE** | 8-allele dual **36.13%**; 17-allele dual **48.81%** tier A+B Chile (`PLAN_A_CHILE_POPULATION_COVERAGE.md`) |
| IEDB cross-check (local) | **DONE** | `PLAN_A_IEDB_CROSSCHECK.md` — **48.81%** reproduced from upload TSV |
| Compute output package (tiers + coverage) | **DONE** | `compute_package/COMPUTE_CANDIDATES.md` |
| 9P3I structural patch ↔ GP linear map | **DONE** (proxy) | **27/28** mapped via global alignment; **0/28** in C-terminal exposed patches → `PLAN_A_STRUCTURAL_PATCH_MAP.json` |
| Chile expanded HLA panel (17 alleles) | **DONE** | Dual-tool on 17 alleles — **247** pairs; tier A+B Chile **48.81%** |
| Full-GP MultiQC mirror (not 90-aa smoke) | **DONE** | `plan_a_epitope/multiqc_full_gp/` + `FigA4_multiqc_summary.png` |

**Verdict:** Strongest track. Epitope ranking is science-driven (consensus + surface + population). Structural patch overlap is a **negative** for C-terminal exposure windows — state explicitly in claims. NetChop/TAP remains optional enhancement.

---

## Plan B (codon / mRNA construct)

| Gate | Status | Evidence / blocker |
| --- | --- | --- |
| Real 3414-nt Q9E006 ladder | **DONE** | Plan B manuscript v1.2 |
| Supplement-only framing (not deployable vaccine) | **DONE** | No liver LNP retarget, no pKa 6.2–6.8, no ectodomain-only variant |
| In silico LNP retarget + construct variants | **NOT DONE** | Science gap if claiming mRNA product |

**Verdict:** Workflow QA / supplement only. **Do not** submit as standalone vaccine science.

---

## Inhibitor (methods funnel)

| Gate | Status | Evidence / blocker |
| --- | --- | --- |
| ZINC150 Vina + ADMET triage | **DONE** | `zinc150_screen/` |
| INH-01–05 + aspirin MD/MM-GBSA | **DONE** (short MD) | ~1 ns; ECR ambertools-gromacs-nf:1.2.0 |
| MM-GBSA protocol QC (aspirin control) | **FAIL** | Aspirin ΔG_bind ≈ −13 kcal/mol — ranking not diagnostic |
| Per-compound pose QC | **DONE** | INH-01–05 ligand RMSD **0.20–0.38 nm** (batch on `md/trajectory.xtc`); INH-03 protein RMSD ~0.66 nm + MM-GBSA outlier |
| Ensemble docking ZINC top-5 (deposit conformers) | **DONE** | Reconciled `20260529T053215Z`; **0/5** improved vs rigid (honest negative) |
| Ensemble docking ZINC top-15 | **DONE** | Recovered `20260603T055454Z` — 5 deposit conformers scored; honest negative on deposit-only ranking |
| Ligand RMSD from trajectories | **DONE** | `LIGAND_RMSD_BATCH.json` — 5/5 compounds |
| ZINC600 full screen | **DONE** | **600/600** merged; top hit **−6.527** kcal/mol |
| Z600-R1 pose QC (GROMACS) | **DONE** | Ligand RMSD **0.26 nm** PASS; **INH-01** remains compute lead |
| Ensemble ZINC600 top-5 | **DONE** | `20260605T025716Z` reconciled; **4/5** improved vs rigid (Δ ≤ 0.14 kcal/mol; **INH-01** unchanged) |
| Publication ZINC HTS (5k dock) | **DONE** | best **−6.952**; INH-01 **#79** |
| Publication top-20 purchasability | **DONE** | `PUBLICATION_ZINC_TOP20_PURCHASABILITY.md` |
| INH-01 generative Vina | **DONE** | best **−7.004** vs pub **−6.952** (Vina only) |
| Ensemble pub top-20 + gen top-5 | **DONE** | `20260607T000744Z` **10/20** improved (best **−7.562** 9P3Y); gen **2/5** improved, best gen rigid **−7.004** → ensemble **−6.969** |
| Post-HTS QC report | **DONE** | `post_hts_qc/POST_HTS_QC_REPORT.md` |
| Publication inhibitor shortlist refresh | **DONE** | `wet_lab_package/INHIBITOR_COMPOUND_SHORTLIST.md` (pub tier; INH-01 MD lead) |

**Verdict:** Methods demonstration only. **INH-01** is the defensible Vina + pose-QC lead; **do not** rank series by MM-GBSA until protocol passes. See `inhibitor_science_qc/INHIBITOR_SCIENCE_QC.md`.

---

## Cross-track rules

1. **MHC predictors:** MHCnuggets + MHCflurry only (see `PLAN_A_MHC_PREDICTOR_SURVEY.md`). Do not introduce NetMHCpan.
2. **Plan B is not #1 on translational science** — only on pipeline completeness / CRO demo lens.
3. **Half-finished compute ≠ finished science** — reconcile artifacts, apply QC gates, integrate tiers before manuscript language.

---

## Commands (regenerate science artifacts)

```bash
python3 research/anti-virus/scripts/analyze_plan_a_population_coverage.py
python3 research/anti-virus/scripts/crosscheck_plan_a_chile_iedb.py
python3 research/anti-virus/scripts/assemble_wet_lab_candidates.py \
  --publication-run research/anti-virus/runs/publication_20260528T223525Z
python3 research/anti-virus/scripts/reconcile_ensemble_docking.py \
  research/anti-virus/science_sprint/runs/20260529T053215Z/track_inh_ensemble
python3 research/anti-virus/scripts/recover_galaxy_ensemble_run.py
python3 research/anti-virus/scripts/recover_chile_mhcflurry_panel.py
python3 research/anti-virus/scripts/build_inhibitor_science_qc.py
```
