# ANDV campaign — plan design survey (second pass)

**Date:** 2026-06-07  
**Run:** `publication_20260528T223525Z`  
**Scope:** Audit Plan A, Plan B, and Inhibitor tracks before manuscript / wet-lab claims.

---

## Executive summary

| Track | Science verdict | Primary blocker |
| --- | --- | --- |
| **Plan A** | Strongest translational track | Manual IEDB web upload; wet-lab MB list stale vs HC tiers |
| **Plan B** | Supplement / workflow QA only | Codon count mismatch (737 vs 539); no deployable LNP |
| **Inhibitor** | Methods funnel + INH-01 MD lead | MM-GBSA invalid; generative “beats HTS” only on rigid Vina |

---

## Plan A (vaccine / epitope)

### What is solid

- **47** strict dual-tool consensus pairs (MHCnuggets + MHCflurry).
- Science tiers: **4 A + 24 B** surface epitopes (`PLAN_A_SCIENCE_TIERS.json`).
- Chile tier A+B coverage **48.81%** (17-allele strict dual) — locally reproduced from upload TSV (`PLAN_A_IEDB_CROSSCHECK.json`).
- Full-GP MultiQC on 45k-row run (not 90-aa smoke).
- Structural patch map: **0/28** tier A+B peptides in 9P3I C-terminal exposed patches (honest negative).

### Gaps found

1. **Wet-lab MB list misaligned:** `WET_LAB_CANDIDATES.md` Track A uses rank-sorted binders (MB-01 = cytoplasmic `ATESALQAHY`). Compute package uses **HC-01…15** from science tiers (tier C excluded). **Action:** regenerate compute package; retire MB-* naming for tier-ranked candidates.
2. **Missing regenerate scripts:** Gates reference `analyze_plan_a_mhc_consensus.py`, `build_plan_a_science_tiers.py`, `analyze_plan_a_proteasomal_processing.py` — not in repo. **`analyze_plan_a_population_coverage.py` restored** (2026-06-07).
3. **Conservation overlap counts differ** across docs (18 vs 10 vs 0) depending on k-mer length, full-GP vs ectodomain, and tier filter. Use **tier A+B Chile upload TSV** as canonical for population claims.
4. **IEDB web audit pending:** Local cross-check PASS; human upload to [IEDB Population Coverage](https://tools.iedb.org/population/) still required.

### Recommended claims

- Lead with **tier A/B dual consensus + GPC surface + 48.81% Chile coverage**.
- State C-terminal structural exposure as **negative** for patch-based vaccine design.
- Do not cite 90-aa smoke Table1 or MB-01 cytoplasmic peptide.

---

## Plan B (codon / mRNA)

### What is solid

- Full **3414-nt** Q9E006 construct ladder documented (manuscript v1.2 supplement).
- RNA2D, LNP pKa, spike/NP-PK analyses complete as **workflow demonstration**.

### Gaps found

1. **Codon optimization count mismatch:** Batch reported **737/1138** optimized codons vs local FASTA **539/1138**. Needs reconciliation before citing codon metrics.
2. **LNP pKa 9.5 SUBOPTIMAL**, liver targeting — documented negatives; P0 gate “supplement only” is correct but easy to over-read as success.
3. **Missing:** `generate_manuscript_plan_b_figures.py`, `launch_plan_b_remaining.py`.

### Recommended claims

- **Supplement / pipeline QA only** — not a deployable vaccine product.
- Do not claim liver-retargeted LNP or optimal pKa without new compute.

---

## Inhibitor (structure-guided HTS)

### What is solid

- Publication ZINC funnel: 42,128 → 5,006 docked; **4,971** scored; best rigid **−6.952** (BBAA).
- INH-01 **#79** in pub deck but **MD + pose QC lead** (RMSD 0.41 nm).
- ZINC600 = **blog/methods tier only** (`ZINC600_LIBRARY_PROVENANCE.md`).
- Post-HTS ensemble QC complete (see below).

### Gaps found

1. **MM-GBSA ranking invalid:** Aspirin control **−13.05 kcal/mol** — do not rank series by MM-GBSA.
2. **Generative vs HTS:** Local medchem enumeration best rigid **−7.004** beats pub **−6.952**, but ensemble **−6.969** (worse than rigid). No pose QC on generative hits.
3. **REINVENT4 Batch path broken** (Nextflow compile); local `rdkit_brics_generation` stub retained 0 compounds. Label workflows honestly as medchem enumeration, not REINVENT4.
4. **Wet-lab shortlist was ZINC150/MM-GBSA-ranked** — refreshed to publication tier (2026-06-07).

### Post-HTS ensemble results

| Panel | N | Improved vs rigid | Strongest ensemble |
| --- | ---: | ---: | --- |
| Publication top-20 | 20 | **10/20** | **−7.562** kcal/mol (ZINC828873353, 9P3Y) |
| INH-01 generative top-5 | 5 | **2/5** | **−6.969** kcal/mol (rigid best −7.004 **worsened**) |

Artifacts: `science_sprint/runs/20260607T000744Z/`, `20260607T002113Z/`; report `post_hts_qc/POST_HTS_QC_REPORT.md`.

### Recommended claims

- Primary HTS = **publication 5k Vina** on target-informed multi-tranche deck.
- **INH-01** = compute lead for SPR/pseudotype (Vina + MD), not top rigid rank.
- Ensemble rescoring **can** improve pub chemotypes (10/20) but is **not uniform**; generative rigid winner does not survive ensemble.
- No nM potency or lead-series claims without biophysical validation.

---

## Cross-track policy (unchanged)

1. MHC predictors: **MHCnuggets + MHCflurry only** (no NetMHCpan).
2. Plan B is not #1 on translational science.
3. Half-finished compute ≠ finished science — reconcile artifacts before manuscript language.

---

## Priority actions (post-survey)

| P | Action | Status |
| --- | --- | --- |
| P0 | IEDB web upload (`PLAN_A_CHILE_POP_COVERAGE_INPUT.tsv`) | Manual pending |
| P0 | Align wet-lab epitope list with HC tiers | Regenerate compute package |
| P1 | Manuscript v1.3 ensemble + generative sections | Updated 2026-06-07 |
| P1 | Restore `analyze_plan_a_population_coverage.py` | **Done** |
| P1 | Refresh inhibitor shortlist (publication tier) | **Done** |
| P2 | Plan B codon reconciliation | Open |
| P2 | Fix or rename REINVENT4 Nextflow module | Open |
