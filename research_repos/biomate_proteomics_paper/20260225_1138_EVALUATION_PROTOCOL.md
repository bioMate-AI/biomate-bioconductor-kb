# Proteomics Paper: Evaluation Protocol and Dataset Plan
**Date:** 2026-02-25 11:38
**Status:** Protocol draft — pending innovation survey results
**Links to:** `20260225_1138_PROTEOMICS_PAPER_PLAN.md`

---

## Product Benefit Being Measured

**The claim:** BioMate catches proteomics quality failures before downstream analysis runs — specifically: failed pulldowns before wet-lab validation, bad phosphoenrichment before site quantification, and invalid compound structures before ADMET prediction.

**The counterfactual:**
- Failed pulldown discovered after 6 weeks of wet-lab target validation ($80K, 47 false-positive interactors)
- Bad phosphoenrichment discovered after all phosphosites are quantified (wasted LC-MS time, wrong MOA conclusion)
- Invalid SMILES silently pass ADMET prediction (wrong compound predictions drive wrong chemistry decisions)

---

## Experiment 1: Quality Parity on Standard DDA (does BioMate match expert QC review?)

**Question:** On a high-quality, well-characterised dataset, does BioMate produce the same protein list and quality metrics as an expert proteomics analyst doing manual QC review?

**Dataset:** PXD000001 (PRIDE — Nagaraj et al. 2011 MCP, HeLa deep proteome)
- ~10,000 proteins identified, published gold standard
- Widely used benchmark — reviewers will recognise it
- MaxQuant output files publicly available

**Protocol:**
1. Download raw files + MaxQuant output from PRIDE PXD000001
2. Run BioMate QC governance layer on MaxQuant outputs
3. Record: all gates fired, all advisory items, final pass/fail decision per sample
4. Expert proteomics analyst reviews same MaxQuant output manually (without BioMate)
5. Compare: protein FDR, CV per replicate, missed cleavage flag rate, oxidation flag rate

**Success criterion:** BioMate and expert analyst reach identical pass/fail decision on ≥ 95% of samples. No false positives (good samples incorrectly halted).

**Key metric:**
> "BioMate matched expert QC decisions on 98% of PXD000001 samples (X/Y) and identified Z quality issues the expert also flagged, in 8 minutes vs 45 minutes of analyst time."

---

## Experiment 2: Protocol-Aware Profile Validation (phosphoproteomics false-positive elimination)

**Question:** Does applying a standard DDA profile to phosphoproteomics data produce false-positive QC failures that the phospho profile correctly resolves?

**Dataset:** PXD003452 (PRIDE — Sharma et al. 2014 Nature Methods, deep mouse brain phosphoproteome)
- 50,000+ phosphosites, canonical phosphoproteomics benchmark
- Phosphopeptide enrichment with TiO2 — inherently lower PSM counts than unenriched

**Protocol:**
1. Download MaxQuant output from PXD003452
2. Run BioMate with `proteomics_standard` profile
3. Record: which gates fire (expect missed cleavage and low PSM count warnings due to enrichment)
4. Run BioMate with `proteomics_phospho` profile
5. Record: which gates fire (expect phosphosite localization gate to be enforced instead)
6. Compare pass/fail decisions between profiles

**Expected result:**
- Standard profile: flags low overall PSM count (misleading — enrichment reduces non-phospho peptides by design)
- Phospho profile: passes PSM count (adjusted threshold); enforces phosphosite localization score > 0.75

**Headline metric:**
> "Standard DDA QC profile produces X false-positive quality flags on phosphoproteomics data. `proteomics_phospho` profile eliminates these while correctly enforcing phosphosite localization requirements."

---

## Experiment 3: Failed Pulldown Detection (the core drug discovery value)

**Question:** Does BioMate's enrichment ratio gate detect a failed chemoproteomics pulldown before downstream analysis? How many false-positive protein interactors does this prevent?

**Why this matters:** In drug target identification, a failed pulldown (poor bead coupling, insufficient drug loading, degraded protein) produces a list of proteins that bind the bead matrix — not the drug. These are followed up in wet-lab validation at $1,000–5,000 per protein per assay.

### 3a: Simulated failed pulldown

**Dataset:** PXD000001 (HeLa proteome) — repurposed as simulated pulldown

**Protocol:**
1. Use 3 technical replicates from PXD000001 as "input proteome"
2. Artificially downsample 3 additional replicates to 10% intensity (simulates bead-only pulldown with minimal enrichment)
3. Calculate enrichment ratio: prey intensity / input intensity for each protein
4. Run BioMate enrichment ratio gate (threshold: prey/input > 3×)
5. Record: number of proteins that pass the gate with and without BioMate governance
6. Cross-reference passing proteins with known contaminants (CRAPome database — common mass spec contaminants)

**Expected result:**
- Without gate: all proteins from downsampled replicates pass to downstream analysis
- With gate: enrichment gate fires on 3 failed replicates; proteins excluded from analysis
- Contaminant proteins (CRAPome members) are disproportionately found in the failed-replicate list

**Headline metric:**
> "BioMate's enrichment ratio gate excluded X proteins from 3 simulated failed pulldown replicates. Y% of excluded proteins were known contaminants (CRAPome). Z false-positive drug target candidates prevented."

### 3b: Real pulldown dataset (if collaborator data available)

**Dataset:** Real chemoproteomics pulldown from pharma/CRO collaborator (de-identified)
- Need: at least one batch that includes failed samples (low coupling efficiency)
- Compare: proteins identified with and without enrichment ratio gating

---

## Experiment 4: SMILES Structure QC (drug discovery compound library)

**Question:** What fraction of a real drug-like compound library has SMILES errors that BioMate catches before ADMET prediction? What is the impact on ADMET output quality?

**Dataset A: ChEMBL random sample**
- Download 1,000 random ChEMBL compounds (SMILES strings, public)
- Run through BioMate SMILES QC gate (RDKit sanitize + salt check + stereochemistry)
- Cross-reference flagged compounds with Whitehead et al. 2022 known-error catalog

**Dataset B: ADMET accuracy test**
- Take 50 compounds with known experimental ADMET values (from ChEMBL bioactivity data: LogP, aqueous solubility, hERG IC50)
- Run all 50 through ADMET prediction: once with BioMate SMILES QC pre-filter, once without
- Compare predicted vs experimental values for valid vs invalid SMILES
- Expected: invalid SMILES produce systematically biased ADMET predictions

**Protocol:**
1. Run 1,000 ChEMBL compounds through BioMate SMILES gate
2. Record: % flagged for each error type (invalid, unsanitizable, salt present, undefined stereo, MW > 900)
3. For 50-compound ADMET test: compare mean absolute error (MAE) of predictions: BioMate-filtered vs unfiltered
4. Show that excluding invalid SMILES improves ADMET prediction MAE

**Headline metrics:**
> "BioMate flagged X% of ChEMBL compounds for SMILES errors before ADMET prediction, consistent with Whitehead et al. 2022 (15%). Excluding flagged compounds reduced ADMET prediction MAE by Y%."

---

## Experiment 5: Plasma Biomarker Profile Validation

**Question:** Does the `proteomics_plasma_biomarker` profile correctly apply tighter CV thresholds appropriate for depleted plasma, without over-flagging valid plasma data?

**Dataset:** PXD010154 (PRIDE — Geyer et al. 2017 Cell Systems, plasma DIA proteomics)
- Landmark plasma proteomics paper
- 1,000+ proteins across 20 plasma samples

**Protocol:**
1. Download DIA-NN output from PXD010154
2. Run with `proteomics_standard` profile
3. Run with `proteomics_plasma_biomarker` profile (CV < 15%, missing value < 30%)
4. Record: number of proteins flagged by each profile
5. Cross-reference flagged proteins with SomaScan/Olink panel (proteins validated by orthogonal methods)

**Success criterion:** `proteomics_plasma_biomarker` profile correctly flags low-reproducibility proteins that are not confirmed by orthogonal panels, without flagging high-confidence proteins that appear in all three platform types (SomaScan, Olink, DIA-NN).

---

## Experiment 6: Non-Expert Usability

**Question:** Can a medicinal chemist or wet-lab biologist with no proteomics bioinformatics training run a complete MaxQuant QC workflow using BioMate?

**Participants:** 5–8 people: medicinal chemists, biochemists, cell biologists — none with MaxQuant or bioinformatics experience

**Task A (proteomics):** Given pre-run MaxQuant output files (uploaded to BioMate), trigger QC governance and interpret the result

**Task B (SMILES):** Given a compound SMILES string, run ADMET prediction through BioMate and interpret the QC gate output

**Metrics:**
- Task A completion rate (target ≥ 70%)
- Task B completion rate (target ≥ 85% — simpler task)
- Time to first actionable result (target < 15 min)
- Number of support requests
- User satisfaction score (1–5, target ≥ 4.0)

---

## Metrics Summary Table

| Metric | Experiment | Target | Failure threshold |
|---|---|---|---|
| Expert QC decision match rate | Exp 1 | ≥ 95% | < 85% |
| Analyst time saved | Exp 1 | ≥ 80% | < 50% |
| False-positive rate on good DDA data | Exp 1 | < 5% | > 15% |
| Profile false-positive elimination (phospho) | Exp 2 | X flags → 0 | Still flags > 50% |
| Enrichment ratio: CRAPome overlap in excluded proteins | Exp 3a | > 60% | < 30% |
| SMILES error detection rate | Exp 4 | ~15% (matches Whitehead 2022) | < 5% or > 40% |
| ADMET MAE improvement after SMILES QC | Exp 4 | ≥ 10% MAE reduction | < 5% |
| Plasma biomarker profile specificity | Exp 5 | Flags low-orthogonal proteins | Flags high-confidence proteins |
| Non-expert task completion | Exp 6 | ≥ 70% | < 50% |

---

## Compute and Resource Budget

| Item | Cost |
|---|---|
| PRIDE dataset download (PXD000001, PXD003452, PXD010154) | Free (public) |
| MaxQuant processing on EC2 (c6i.8xlarge, ~4h per dataset) | ~$15 per dataset |
| DIA-NN processing on EC2 | ~$10 per dataset |
| ChEMBL SMILES QC (CPU only, fast) | ~$2 |
| **Total compute** | **~$60** |
| Expert analyst time (for comparison arm) | Need collaborator agreement |
| Usability sessions (6 participants × 60 min) | Scheduling only |

**Total budget: ~$60 compute + analyst time from co-author lab**

---

## What Must Be Built Before Running Experiments

| Prerequisite | Status | Effort |
|---|---|---|
| `_parse_maxquant_metrics()` — `summary.txt`, `proteinGroups.txt`, `peptides.txt` | ❌ Not built | 2 days |
| `_parse_diann_metrics()` — `report.tsv`, `report.stats.tsv` | ❌ Not built | 1 day |
| `_check_qc_thresholds()` proteomics branch (GOLD PSM FDR, SILVER CV, etc.) | ❌ Not built | 1 day |
| Named profiles: `proteomics_standard`, `proteomics_phospho`, `proteomics_plasma_biomarker` | ❌ Not built | 0.5 day |
| Enrichment ratio gate (prey/input calculation from label-free intensities) | ❌ Not built | 1 day |
| SMILES QC gate (RDKit sanitize + MolVS + MW check) | ❌ Not built | 2 days |
| Test suite: `TestProteomicsQCDomain` (25 tests) | ❌ Not built | 1 day |

**Total build time before experiments can run: ~9 days**

---

## Timeline

| Week | Action |
|---|---|
| 1–2 | Build all parsers and QC governance layer (9 days) |
| 3 | Download PRIDE datasets; run Experiments 1 and 4 (SMILES QC) |
| 4 | Run Experiments 2 and 5 (profile validation) |
| 5 | Run Experiment 3 (simulated failed pulldown) |
| 6 | Usability sessions (Experiment 6) |
| 7–8 | Analyse results; draft figures; contact collaborator for real pulldown data |
