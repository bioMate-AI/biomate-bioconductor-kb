# Study Proposal
## Cryo-EM Structural Pharmacology to Human Response Prediction

**Proposing parties:** BioMate AI · Partner Structural Biology / Drug Discovery Lab  
**Study organisation:** Phase 0 (internal validation, 2 weeks) → Phase 1 (partner study on published targets, 3 months) → Phase 2 (novel research on partner's own targets, 6–9 months)  
**Compute cost to partner:** $0  
*April 2026 · Companion to BioMate_DrugDiscovery_Extended_Study_Proposal.md*

---

## Overview

This proposal evaluates BioMate's end-to-end structural pharmacology pipeline: cryo-EM structure determination → drug binding analysis → ADMET profiling → translational PKPD → human response prediction, with a wet lab feedback loop closing the DMTA cycle.

Three disease areas are covered, each tied to a specific molecular class:

| Disease Area | Molecular Target Class | Specific Target | Therapeutic Modality |
|---|---|---|---|
| **Infectious disease** | mRNA therapeutic + small molecule | SARS-CoV-2 (spike mRNA vaccine; Mpro small molecule inhibitor) | mRNA vaccine design + antiviral drug design |
| **Obesity / weight loss** | Membrane protein (class B GPCR) | GLP-1 Receptor (GLP-1R) | Peptide and small molecule agonist |
| **Cancer** | Membrane protein (receptor tyrosine kinase) | EGFR with resistance mutations | Allosteric kinase inhibitor |

The study is structured so that **Phase 0 (internal validation) takes 2 days and requires no new experiments** — it runs entirely on published datasets that already have known gold-standard answers. Phases 1 and 2 build on that validated pipeline, first replicating published drug discovery work as a quality check, then applying BioMate to new research questions the partner has not yet answered.

The full platform evaluation completes in 10 days. Research collaboration (Phases 1 and 2) begins immediately after the Day 10 go/no-go decision.

---

## Phase 0: Internal Validation (2 Weeks, No Partner Input Required)

Before the partner commits time or samples, BioMate runs its full pipeline on targets where the answer is already known. If BioMate cannot reproduce published results on public data, the pipeline needs fixing before any collaboration begins. If it can, both parties have quantitative confidence in what BioMate will do on new data.

Phase 0 runs entirely from public databases (EMPIAR, PDB, ChEMBL, NCBI) and takes 1–2 weeks of compute time.

---

### P0-A: Cryo-EM Pipeline Validation — EMPIAR-10061 (β-galactosidase)

**What it is:** The canonical cryo-EM benchmark dataset. *E. coli* β-galactosidase in complex with a cell-permeant inhibitor (PETG), 38,088 micrographs on a Titan Krios with K2 detector, published structure at 2.2 Å resolution (EMDB-2984, PDB 5A1A; Bartesaghi et al., *Science* 348:1147–1151, 2015; doi:10.1126/science.aab1576). This dataset is the field-standard benchmark used to validate every new cryo-EM processing pipeline.

**Why this target:** No drug discovery relevance, but ideal for pipeline validation. The published structure is at near-atomic resolution with extensively documented quality metrics. The micrographs are publicly available through EMPIAR (https://www.ebi.ac.uk/empiar/EMPIAR-10061/).

**BioMate workflow:**
1. Import micrographs from S3 (EMPIAR-10061 download)
2. Patch motion correction + CTF estimation
3. Blob picking → 2D classification → template picking
4. 3D ab initio → NU-refinement
5. FSC curve + local resolution map

**Gold standard to match:**
- Final resolution: ≤ 2.5 Å (published: 2.2 Å; reproducibility target allows 0.3 Å slack)
- FSC 0.143 curve shape consistent with published EMDB-2984 curve
- MolProbity Ramachandran outliers ≤ 1% (published model PDB 5A1A: 0.3%)
- Runtime: ≤ 10 hours on g6.2xlarge AWS (8 NVIDIA L4 GPUs)

**Pass/fail:** Single metric — does BioMate reach ≤ 2.5 Å? If yes, cryo-EM pipeline is validated.

**License note:** P0-A requires a CryoSPARC license. CryoSPARC does not allow redistribution; each institution must hold its own license (academic licenses are free via cryosparc.com). BioMate cannot supply a CryoSPARC license on the partner's behalf. If the partner already holds a CryoSPARC license, P0-A runs within BioMate's cloud infrastructure using that license key. If no license is available, P0-A is substituted with a RELION 4.0 reconstruction of the same EMPIAR-10061 dataset (pass criterion adjusted to ≤ 3.0 Å, reflecting RELION's typical resolution for this dataset).

---

### P0-B: mRNA Design Validation — Moderna mRNA-1273 (SARS-CoV-2 Spike)

**What it is:** The mRNA sequence encoding the SARS-CoV-2 spike protein used in Moderna's mRNA-1273 vaccine. The design principles are published (Jackson et al., *N Engl J Med* 383:1920–1931, 2020, doi:10.1056/NEJMoa2022483; Corbett et al., *Nature* 586:567–571, 2020, doi:10.1038/s41586-020-2622-0). Key design parameters include 2-proline prefusion stabilisation (K986P, V987P; first reported in Wrapp et al., *Science* 367:1260–1263, 2020, doi:10.1126/science.abb2507) and codon optimisation for human expression. The mRNA-1273 coding sequence is deposited at GenBank accession **OK120841.1** (https://www.ncbi.nlm.nih.gov/nuccore/OK120841.1).

**BioMate workflow (mRNA design arm):**
1. Input: SARS-CoV-2 spike coding sequence from NCBI reference genome MN908947.3 (https://www.ncbi.nlm.nih.gov/nuccore/MN908947.3), ORF S (positions 21563–25384) or deposited mRNA-1273 sequence OK120841.1
2. Apply 2P stabilisation mutations (K986P, V987P) to the amino acid sequence
3. Run BioMate codon optimisation for *Homo sapiens* expression (maximise CAI, eliminate rare codons with usage < 10%, reduce CpG dinucleotide frequency)
4. Run ViennaRNA RNAfold on the optimised sequence to assess secondary structure at the start codon region (target: open structure at 5' end with minimum free energy > −25 kcal/mol for the first 50 nt, ensuring ribosome access)
5. Design 5'-UTR (Kozak consensus GCCACCATG) and 3'-UTR (human β-globin 3'-UTR for stability)
6. Predict poly-A tail length for optimal half-life

**Gold standard to match:**
- Codon Adaptation Index (CAI) ≥ 0.90 for human expression (independently optimised mRNA vaccine sequences achieving CAI > 0.95 are reported in analyses of mRNA-1273 and BNT162b2; Park et al., *Comput Struct Biotechnol J* 2021, doi:10.1016/j.csbj.2021.07.016)
- No in-frame stop codons introduced during codon optimisation (hard pass/fail)
- Predicted 5'-proximal structure is less stable (higher MFE) than the unmodified natural sequence at the same region — confirming that optimisation opens the 5' end for ribosome entry
- GC content 45–65% after optimisation (consensus range for stable human-expressed mRNA)

**Pass/fail:** CAI ≥ 0.90 AND no stop codons AND improved 5' MFE vs. natural sequence. This validates BioMate's mRNA design workflow against the most widely tested mRNA sequence in history.

---

### P0-C: Small Molecule Docking Validation — Mpro + Nirmatrelvir (PDB 7RFS)

**What it is:** SARS-CoV-2 main protease (Mpro) in complex with nirmatrelvir (the active component of Paxlovid). Published X-ray structure at 1.9 Å (PDB 7RFS, Owen et al., *Science* 2021). Nirmatrelvir forms a covalent bond with Cys145; the non-covalent contacts define the pharmacophore.

**Why this target:** Mpro is the most extensively characterised antiviral drug target of the past decade. The nirmatrelvir binding pose is at 1.9 Å resolution — the most accurate possible reference for docking validation. Over 200 Mpro structures are in the PDB.

**BioMate workflow:**
1. Load PDB 7RFS; extract the nirmatrelvir-free Mpro coordinates (chain A, remove ligand) as the docking receptor
2. Load nirmatrelvir SMILES (from PubChem CID 145996610) as the docking query
3. Run AutoDock Vina docking with default parameters, exhaustiveness=32
4. Report top 9 poses; RMSD vs. published crystal pose for each

**Gold standard to match:**
- Top-ranked pose RMSD ≤ 2.0 Å vs. crystal pose (PDB 7RFS, ligand SYN)
- All 5 key hydrogen bond contacts reproduced: His163(NH)–O=nirmatrelvir, Glu166(NH)–O=, Gln189(NH)–O=, Thr190(OH)–N=, His41 (catalytic dyad proximity)
- Nirmatrelvir ranks #1 or #2 in a 100-compound retrospective screen mixing nirmatrelvir with 99 property-matched decoys from the DUD-E database

**Pass/fail:** RMSD ≤ 2.0 Å AND H-bond contacts ≥ 4 of 5. If docking fails this on a 1.9 Å reference structure, the docking protocol needs adjustment before any prospective screening is run.

---

### P0-D: Membrane Protein Docking Validation — GLP-1R + Semaglutide (PDB 7KI0)

**What it is:** GLP-1 receptor in complex with semaglutide and Gs heterotrimer. Published cryo-EM structure at 2.5 Å (PDB 7KI0; Zhang X, Belousoff MJ, Liang YL, Danev R, Sexton PM, Wootten D et al., *Cell Reports* 36:109374, 2021, doi:10.1016/j.celrep.2021.109374; Sexton/Wootten lab, Monash University).

**Why this target:** GLP-1R is the hottest drug target of the 2020s (semaglutide = Ozempic/Wegovy; tirzepatide = Mounjaro). The semaglutide binding mode at 2.5 Å is the gold standard pharmacophore for GLP-1R agonism. Any GLP-1R drug design workflow must reproduce this before generating novel candidates.

**BioMate workflow:**
1. Load PDB 7KI0; identify GLP-1R transmembrane domain + extracellular loops as the binding cavity
2. Extract semaglutide peptide coordinates; convert to SMILES representation
3. Run pharmacophore model generation from the GLP-1R binding site (key features: H-bond donors at Arg190, Glu127; hydrophobic pocket at Leu141, Val194)
4. Validate pharmacophore: semaglutide must match ≥ 4 of 5 features
5. Dock 10 GLP-1R agonists with known EC50 (from ChEMBL) + 90 inactive compounds → check enrichment

**Gold standard to match:**
- Semaglutide pharmacophore match: ≥ 4 of 5 features mapped
- AUC-ROC for ranking known GLP-1R agonists vs. inactives: ≥ 0.75
- Published active compounds with EC50 < 100 nM all ranked in top 25 of a 100-compound screen

**Pass/fail:** Pharmacophore match ≥ 4/5 AND AUC-ROC ≥ 0.75.

---

### P0-E: PKPD Model Validation — Semaglutide in Humans

**What it is:** The published population PK model for semaglutide in humans (Overgaard RV, Delff PH, Petri KCC, Anderson TW, Flint A, Ingwersen SH. "Population Pharmacokinetics of Semaglutide for Type 2 Diabetes." *Diabetes Therapy* 10:649–662, 2019, doi:10.1007/s13300-019-0581-y, PMID: 30788808), validated against the SUSTAIN-1 Phase 3 trial (Sorli C et al., *Lancet Diabetes Endocrinol* 5:251–260, 2017, doi:10.1016/S2213-8587(17)30013-X, PMID: 28110911). SUSTAIN-1 was a 30-week trial; semaglutide 1.0 mg SC once weekly produced a body weight reduction of −4.53 kg (95% CI −5.34 to −3.72 kg) vs. placebo at 30 weeks.

**BioMate workflow:**
1. Load semaglutide PK parameters from Overgaard et al. (half-life ~168 h, SC bioavailability ~89%, Vd ~12.5 L as reported)
2. Run BioMate's 2-compartment SC PK simulation at 1 mg dose, once weekly for 30 weeks
3. Map predicted plasma Cmax (steady-state) through the GLP-1R Emax PD model to predicted appetite suppression
4. Predict absolute body weight loss at 30 weeks

**Gold standard to match:**
- Predicted steady-state Cmax: within 30% of the mean value reported in Overgaard et al.
- Predicted body weight loss at 30 weeks: −3 to −6 kg (SUSTAIN-1 observed: −4.53 kg; allow model uncertainty of ±1.5 kg given variability in trial population and model assumptions)
- Predicted AUC at steady state within 30% of published value

**Pass/fail:** Predicted Cmax and 30-week body weight loss within the stated ranges.

---

### Phase 0 Summary

All 5 validation checks run in parallel on Day 1–2, before any partner time is required. P0-B through P0-E complete within hours; P0-A (cryo-EM, 38,088 micrographs) runs up to 10 hours on GPU compute. The combined wall-clock time fits within 2 days. BioMate delivers a quantitative pass/fail report by end of Day 2. Partner time is not required until P0 passes — with one exception: P0-A requires a CryoSPARC license key from the partner (or defaults to RELION if none is available; see P0-A note above). This is a one-time 5-minute setup action on Day 0, not a research time commitment.

| Check | Data Source | Key Metric | Pass Criterion | Typical Runtime |
|---|---|---|---|---|
| P0-A: Cryo-EM pipeline | EMPIAR-10061 (β-gal; Bartesaghi *Science* 2015) | Final resolution | ≤ 2.5 Å | ~8–10 h |
| P0-B: mRNA design | GenBank OK120841.1; MN908947.3 spike ORF | CAI + stop codons | CAI ≥ 0.90, no stop codons | ~5 min |
| P0-C: Mpro docking | PDB 7RFS (Owen *Science* 2021) | Docking RMSD | ≤ 2.0 Å, ≥ 4/5 H-bonds | ~15 min |
| P0-D: GLP-1R pharmacophore | PDB 7KI0 (Zhang *Cell Rep* 2021) | AUC-ROC | ≥ 0.75 | ~30 min |
| P0-E: Semaglutide PKPD | Overgaard *Diabetes Therapy* 2019; SUSTAIN-1 trial | Body weight at 30w | −3 to −6 kg | ~5 min |

---

## Disease Area 1: Infectious Disease — mRNA Vaccine + Mpro Antiviral

### Scientific Problem

Two complementary approaches address SARS-CoV-2 and emerging infectious disease:
1. **mRNA vaccines** — encode the viral antigen to prime the immune system before infection. The Moderna mRNA-1273 approach is validated but still being optimised (variant coverage, thermostability, mucosal immunity)
2. **Small molecule antivirals** — inhibit viral replication after infection. Nirmatrelvir targets Mpro with Ki ≈ 3 nM (Owen et al., *Science* 2021), but emerging resistance mutations — in particular E166V, which reduces nirmatrelvir potency ~80-fold in enzymatic assays (Ullrich S, Nitsche C. *bioRxiv* 2021; Jochmans D et al., *J Biol Chem* 299:102928, 2023, doi:10.1016/j.jbc.2022.102928) — motivate the design of next-generation inhibitors with a broader resistance profile

BioMate addresses both in parallel for the same virus, demonstrating how the platform covers the full antiviral therapeutic pipeline.

### Arm 1A: mRNA Vaccine Design for Emerging Variants

**Target:** SARS-CoV-2 spike protein (full-length, 2P-stabilised prefusion conformation), updated for the BA.2.86/JN.1 variant clade

**BioMate workflow (building on validated P0-B):**
1. Input: BA.2.86 spike sequence (GISAID accession EPI_ISL_17890055)
2. Apply 6P hexapro stabilisation (6 prolines that improve thermal stability over original 2P; published: Hsieh et al., *Science* 2020)
3. Codon optimisation with BioMate (same pipeline as P0-B, now targeting dendritic cell expression for a mucosal vaccine formulation)
4. Design of the 5'-UTR for IRES-mediated translation enhancement
5. LNP formulation parameter prediction: ionisable lipid pKa optimisation for endosomal escape (SM-102 equivalent pKa = 6.68 ± 0.2)
6. Predict immunogen folding using ESMFold → compare to semaglutide reference structure to confirm correct 2P/6P stabilisation

**Gold standard comparison:** Published mRNA-1273.214 bivalent booster design (Pfizer/BioNTech and Moderna technical briefs, 2022). BioMate's optimised BA.2.86 sequence is compared against the published design approach for equivalent metrics (CAI, predicted expression, predicted LNP encapsulation efficiency).

**Wet lab validation:** Partner performs in vitro transcription of BioMate-designed sequence + lipofection into 293T cells; quantify spike protein expression by Western blot at 24h and 48h. Compare to commercially available mRNA-1273-equivalent as positive control.

**Human response prediction:** BioMate models seroconversion timeline (antibody titre at Day 14, 28) using published mRNA-1273 immunogenicity kinetics (Jackson et al., *NEJM* 2020) as the calibrated PK/PD analogue. Output: predicted % of vaccinees reaching protective antibody titre (≥ 4-fold rise over baseline, WHO seroprotection threshold) at 28 days.

---

### Arm 1B: Mpro Antiviral Drug Design for Resistance-Robust Inhibitor

**Target:** SARS-CoV-2 Mpro, with focus on the clinically-emerging E166V resistance mutation. E166V disrupts the key S1 subsite H-bond network used by nirmatrelvir and reduces enzymatic IC50 by ~80-fold (Jochmans D et al., *J Biol Chem* 299:102928, 2023, doi:10.1016/j.jbc.2022.102928). The E166V substitution is structurally characterised: PDB **8DZ3** (Mpro E166V apo; deposited by the COVID Moonshot consortium, https://fragalysis.diamond.ac.uk/). The goal is to design inhibitors that maintain potency against both WT and E166V.

**BioMate workflow (building on validated P0-C):**

1. **Structural comparison (WT vs. E166V):**
   - Load PDB 7RFS (WT Mpro + nirmatrelvir, 1.9 Å)
   - Load PDB 8DZ3 (E166V Mpro, for apo conformation; partner may supply a drug-bound E166V structure if available)
   - BioMate automatically aligns the structures and identifies which S1 subsite residues shift with E166V
   - Key question: which pharmacophore features of nirmatrelvir are lost at E166V, and what alternative contacts are available?

2. **Resistance-robust virtual screen:**
   - Pharmacophore model generated from the conserved binding site features shared between WT and E166V (His163, His41-Cys145 catalytic dyad, and the S2/S4 hydrophobic sub-pockets are E166V-insensitive)
   - Virtual screen of ChEMBL Mpro actives (>2,000 compounds with IC50 data; https://www.ebi.ac.uk/chembl/target_report_card/CHEMBL3927/) + Enamine HTS library against the conserved pharmacophore
   - Ensemble docking against both WT and E166V structures; compounds ranked by mean score
   - The COVID Moonshot open-science dataset (>15,000 Mpro-tested compounds, all public; https://covid.postera.ai/covid/activity_data) provides the largest existing ground-truth ADMET + Mpro IC50 dataset for training the ranking model

3. **ADMET filter:**
   - hERG IC50 prediction (must be ≥ 30× the Mpro IC50 for safety margin)
   - Oral bioavailability prediction (Caco-2 Papp ≥ 10 × 10⁻⁶ cm/s; solubility ≥ 50 μM)
   - CYP3A4 inhibition prediction (nirmatrelvir's CYP3A4 interaction is a known clinical liability for drug-drug interactions; Montgomery JM et al., *J Med Chem* 2021, PMID: 34797981)

4. **REINVENT4 optimisation (if wet lab IC50 data available from partner):**
   - Seed: top 3 compounds from Steps 2–3
   - Reward: Mpro WT IC50 (50%) + E166V IC50 (50%) + oral bioavailability score
   - 2 DMTA rounds: Round 1 → partner synthesises 3–5 compounds → IC50 measured → Round 2

**Gold standard comparison:**
- Nirmatrelvir IC50 against WT Mpro: ~19 nM (FRET assay; Owen et al. *Science* 2021, PMID: 34726479)
- Nirmatrelvir IC50 against E166V Mpro: ~1.5 μM (~80× shift; Jochmans et al. *JBC* 2023)
- COVID Moonshot dataset provides ground truth: compounds with IC50 < 1 μM against Mpro WT (>200 confirmed actives) must rank in the top 5% of BioMate's virtual screen
- DUD-E-based retrospective enrichment: AUC-ROC for Mpro actives vs. property-matched decoys ≥ 0.80 (Mysinger MM et al., *J Med Chem* 55:6582–6594, 2012, doi:10.1021/jm300687e)

**Human response prediction:**
- 2-compartment PK model for the top compound at 150 mg and 300 mg oral dose
- Viral dynamics model (Ke R, Zitzmann C, Ho DD, Ribeiro RM, Perelson AS. *Proc Natl Acad Sci USA* 118:e2111477118, 2021, doi:10.1073/pnas.2111477118) with compound-specific IC50 substituted in
- Output: predicted time to viral clearance (target: ≤ 5 days, comparable to published nirmatrelvir result in high-risk patients)

---

## Disease Area 2: Obesity / Weight Loss — GLP-1R Membrane Protein

### Scientific Problem

GLP-1R is a class B GPCR — a 7-transmembrane helical membrane protein. All currently approved GLP-1R agonists are peptides (semaglutide, liraglutide, tirzepatide) requiring weekly or daily injection. An **orally bioavailable small molecule GLP-1R agonist** would transform the treatment of obesity and type 2 diabetes. Despite 15 years of effort, no approved small molecule GLP-1R agonist exists (the closest: oral semaglutide = the same peptide formulated with an absorption enhancer, not a true small molecule).

The structural reason for this difficulty is now understood: semaglutide activates GLP-1R by engaging both the extracellular domain (ECD, via the peptide N-terminus) and the transmembrane bundle (via the peptide C-terminus and fatty acid chain). A small molecule must mimic both interactions with MW < 500 Da — a significant medicinal chemistry challenge.

BioMate addresses this computationally: given the 2.5 Å GLP-1R + semaglutide structure (validated in P0-D), can it identify small molecule scaffolds that recapitulate the key pharmacophore features?

### Arm 2A: Small Molecule GLP-1R Agonist Design

**Building on validated P0-D (GLP-1R pharmacophore):**

1. **Pharmacophore analysis of key agonist-receptor contacts (from PDB 7KI0):**
   - His⁷(semaglutide) → Arg190(GLP-1R): critical for receptor activation (His⁷ mutation abolishes activity)
   - Phe⁶(semaglutide) → hydrophobic pocket (Leu141, Val194, Trp297): drives binding selectivity
   - Gly⁴(semaglutide) → Glu127(GLP-1R): backbone H-bond
   - Leu¹³(semaglutide) → Tyr148(GLP-1R): helical region binding
   These 4 contacts define the minimum pharmacophore for GLP-1R agonism

2. **Small molecule screen against the transmembrane binding site:**
   The TM bundle of GLP-1R has a deeper, more enclosed binding site accessible to small molecules. Two published non-peptide GLP-1R agonists establish the gold standard for this screen:
   - **TT-OAD2** (non-peptide oral GLP-1R full agonist, first-in-class; PDB 6ORV, EMDB EMD-20179, 3.0 Å cryo-EM; Zhao P et al., *Nature* 577:432–436, 2020, doi:10.1038/s41586-019-1902-z, PMID: 31915381)
   - **Structural basis for probe-dependent GLP-1R allosterism** (Bueno AB et al., *Nat Chem Biol* 16:1105–1110, 2020, doi:10.1038/s41589-020-0562-2, PMID: 32690941) — characterises the allosteric binding site geometry that small molecules exploit
   - Virtual screen: ChEMBL + ZINC-15 drug-like subset (350k compounds, MW 200–450 Da)
   - Pharmacophore filter against the TM site pharmacophore (H-bond donor to Glu127; hydrophobic to Leu141 pocket; derived from 6ORV TT-OAD2 contacts)
   - Docking against the active-state GLP-1R (PDB 7KI0 semaglutide-bound + PDB 6ORV TT-OAD2-bound ensemble — two active conformations)
   - Rank by mean docking score across both structures

3. **ADMET filter:**
   Unlike Mpro (an intracellular enzyme), GLP-1R is plasma-facing. ADMET requirements emphasise:
   - Oral bioavailability (Caco-2 Papp ≥ 15 × 10⁻⁶ cm/s) — the key differentiation from semaglutide
   - Metabolic stability (microsomal t½ ≥ 60 min human)
   - ClogP 1–4 (polar enough for adequate solubility; lipophilic enough for membrane permeation)

4. **REINVENT4 optimisation:**
   - Seed: top 3 from the TM site screen
   - Reward: GLP-1R cAMP EC50 prediction (QSPR model trained on 87 published GLP-1R small molecule actives from ChEMBL) × 40% + oral bioavailability × 40% + selectivity vs. GLP-2R × 20%
   - 3 DMTA rounds (if partner performs cAMP assay on synthesised compounds)

**Gold standard comparison:**
- **TT-OAD2** (PDB 6ORV; Zhao et al. *Nature* 2020): must rank in top 1% of the 350k compound screen — this is the most demanding test because TT-OAD2 binds a novel allosteric site distinct from peptide contacts, and BioMate must discover it computationally
- **Orforglipron (LY3502970)**, Eli Lilly's oral non-peptide GLP-1R agonist (Phase 3; Frías JP et al., *N Engl J Med* 389:877–888, 2023, doi:10.1056/NEJMoa2302392): must rank in top 5% of the screen — orforglipron's SMILES is available via ChEMBL (CHEMBL4523712) and provides a drug-like positive control with validated human efficacy
- BioMate screen must achieve AUC-ROC ≥ 0.75 on the set of GLP-1R small molecule actives from ChEMBL (>50 compounds with EC50 data at human GLP-1R) vs. property-matched inactives

**Wet lab validation:** Partner performs GLP-1R cAMP accumulation assay (HTRF or ELISA-based) for top 5 BioMate-designed compounds. Gold standard positive control: semaglutide at 1 nM (should give ≥ 80% of maximal cAMP response). Target: at least 1 of the 5 BioMate compounds shows EC50 < 1 μM (partial agonism acceptable for this stage).

**Human response prediction:**
- 2-compartment oral PK model for the predicted best compound at 50, 100, and 300 mg oral dose
- Map predicted free Cmax to GLP-1R occupancy (using Ki from docking-calibrated model)
- Apply semaglutide body weight loss PK/PD model (from P0-E) with the compound-specific EC50 substituted in
- Output: predicted body weight loss at 12 weeks vs. dose; comparison to semaglutide 1 mg SC

---

### Arm 2B: Cryo-EM Structure of Novel GLP-1R Complex (Phase 2 / Novel Research)

**This arm requires partner to have cryo-EM access and a GLP-1R-expressing cell line or purified receptor. It is the Phase 2 novel research component and begins only after Arm 2A is complete.**

The goal: determine the cryo-EM structure of GLP-1R bound to the best BioMate-designed compound from Arm 2A. If a new small molecule GLP-1R agonist with EC50 < 1 μM is identified, its binding mode can be determined by cryo-EM:
- Express GLP-1R in Sf9 cells; co-purify with Gs heterotrimer (standard GLP-1R-Gs complex preparation)
- Add small molecule at 100× EC50 for 30 min at 4°C before vitrification
- Run CryoSPARC pipeline (same as P0-A but for a ~200 kDa complex)
- Resolve small molecule density in the difference map; confirm binding site

This would be the first cryo-EM structure of a BioMate-designed compound bound to GLP-1R — a direct structural validation of the computational prediction.

---

## Disease Area 3: Cancer — EGFR Allosteric Inhibition

### Scientific Problem

EGFR (Epidermal Growth Factor Receptor) is a type I receptor tyrosine kinase — a single-pass transmembrane protein with an extracellular ligand-binding domain and an intracellular kinase domain. It is mutated (L858R, exon 19 deletion) in ~15% of non-small-cell lung cancers. Three generations of ATP-competitive inhibitors have been approved, but resistance has emerged to each:

- Generation 1 (erlotinib, gefitinib): overcome by T790M gatekeeper mutation
- Generation 2 (afatinib): T790M resistance persists
- Generation 3 (osimertinib): T790M bypassed, but C797S acquired resistance now prevalent

C797S eliminates the covalent warhead binding site that all three approved drugs use. No 4th-generation approved drug exists. **Allosteric inhibitors** — binding outside the ATP pocket, at the EGFR dimer interface — bypass C797S entirely.

The allosteric site has been structurally characterised: PDB **5D41** contains the EGFR kinase domain (L858R/T790M) in complex with a close structural analogue of EAI045 at 2.31 Å (Jia Y et al., *Nature* 534:129–132, 2016, doi:10.1038/nature17960, PMID: 27251290). The asymmetric EGFR kinase dimer relevant to allosteric inhibition is described in PDB **2GS6** (Zhang X et al., *Cell* 125:1137–1149, 2006, doi:10.1016/j.cell.2006.05.013). But the first allosteric EGFR inhibitor (EAI045) requires combination with cetuximab for efficacy in vivo, limiting its clinical utility. BioMate's goal: identify allosteric inhibitors that are potent as monotherapy.

### Arm 3A: EGFR Allosteric Inhibitor Design

**Building on published structures (no new cryo-EM needed for Phase 1):**

1. **Allosteric site characterisation:**
   - Load PDB 5D41 (EGFR L858R/T790M kinase domain + structural analogue of EAI045, 2.31 Å; Jia et al. *Nature* 2016)
   - Load PDB 2GS6 (EGFR kinase asymmetric dimer, active/inactive pair; Zhang et al. *Cell* 2006) to understand the dimer interface context
   - BioMate generates pharmacophore for the allosteric site from the 5D41 ligand contacts (hydrophobic pocket at Leu777, Met766; H-bond acceptor at Lys745; consistent with Jia et al. supplementary data)

2. **Virtual screen against allosteric site:**
   - Enamine HTS library (700k compounds) + ChEMBL kinase inhibitor set (50k compounds)
   - Pharmacophore pre-filter (must match ≥ 3 of 4 EAI045-analogue pharmacophore features)
   - Docking against PDB 5D41 (allosteric site only, not ATP pocket)
   - Selectivity filter: compounds must score ≥ 2 kcal/mol worse at the ATP binding site — to avoid ATP-competitive activity that would be blocked by C797S

3. **Resistance mutation screen:**
   - BioMate models the C797S mutation (Cys797Ser substitution) onto the receptor and re-docks all top 20 compounds
   - Compounds whose docking score is ≥ 80% retained in C797S vs. WT are classified as resistance-robust
   - This step exploits the fact that C797S is in the ATP pocket, not the allosteric site — allosteric binders are predicted to be C797S-insensitive by definition

4. **REINVENT4 optimisation:**
   - Seed: top 3 allosteric compounds from virtual screen
   - Reward: allosteric docking score × 40% + predicted IC50 (L858R/T790M/C797S triple mutant) × 40% + ADMET × 20%

**Gold standard comparison:**
- EAI045 EGFR inhibition IC50: **3 nM** against EGFR L858R/T790M at physiological ATP concentration (1 mM ATP); reported as 2 pM only under non-physiological 1 μM ATP assay conditions (Jia et al., *Nature* 534:129–132, 2016, doi:10.1038/nature17960, PMID: 27251290). The 3 nM value at physiological ATP is the pharmacologically relevant number for ranking
- EAI045 is >1,000-fold selective for mutant EGFR over WT EGFR and inactive against a panel of >100 other kinases (Jia et al. 2016 extended data)
- BioMate must rank EAI045 (SMILES from PubChem or as extracted from PDB 5D41) in the top 1% of the 750k compound screen against the allosteric site
- Compounds ranked above EAI045 in the BioMate screen are candidates for synthesis

**Wet lab validation:** Partner performs EGFR kinase inhibition assay (Z-LYTE or LanthaScreen assay format) for top 5 BioMate-designed allosteric compounds, using:
- EGFR WT kinase domain
- EGFR L858R/T790M (standard 3rd-gen resistance model)
- EGFR L858R/T790M/C797S (4th-gen resistance model — the unmet need)
Expected: BioMate compounds maintain IC50 < 500 nM in the triple mutant while EAI045 maintains < 1 nM (as the positive control demonstrating the assay works). A compound with IC50 < 100 nM against the triple mutant would be a significant discovery.

**Human response prediction:**
- 2-compartment oral PK model for top compound at 100, 300, 600 mg dose (typical kinase inhibitor dose range)
- EGFR inhibition PK/PD: map predicted free Cmax to % kinase inhibition using competitive binding model
- Tumour growth inhibition (TGI) model (Simeoni M et al., *Cancer Res* 64:1094–1101, 2004, doi:10.1158/0008-5472.CAN-03-2524, PMID: 14871843) calibrated to published osimertinib TGI data in xenograft models → scale to human
- Output: predicted time to progression vs. dose (target: median time to progression ≥ 6 months at 300 mg, comparable to osimertinib data in C797S-resistant patients in retrospective studies)

---

### Arm 3B: Cryo-EM of EGFR in Lipid Nanodisc (Phase 2 / Novel Research)

Full-length EGFR in a lipid membrane has never been determined at better than 6–8 Å by cryo-EM (the kinase domain crystal structures are all truncated constructs in detergent). Determining the cryo-EM structure of full-length EGFR in a nanodisc with an allosteric inhibitor bound would be a landmark result — capturing both the extracellular domain and the kinase domain dimer in one structure at near-atomic resolution.

This requires:
- Full-length EGFR (residues 1–1210) expressed in Sf9 cells and purified in nanodisc (MSPΔH5 belt protein + POPC:POPE 4:1)
- BioMate processes the cryo-EM data using the same validated CryoSPARC pipeline from P0-A
- Target resolution: 3.5–4.5 Å for the full-length construct (resolution expectation is lower than for soluble proteins due to the flexible extracellular domain)

**This arm is Phase 2 only and begins after Arm 3A validates the allosteric inhibitor series in biochemical assays.**

---

## Complete Workflow: From First Data Point to Human Response Prediction

### 10-Day Pilot Timeline

The pilot evaluates BioMate across 10 days before full research collaboration begins. Partner time commitment is minimal until Phase 1 passes.

| Day | Phase | Activities | Partner Time |
|---|---|---|---|
| 1–2 | **Phase 1 — Internal Validation (P0)** | BioMate runs all 5 P0 checks in parallel on public data. P0-A (cryo-EM, ~10h GPU) runs overnight Day 1→2. P0-B/C/D/E complete within 1 hour. Pass/fail report delivered end of Day 2. | 0 hrs |
| 3–7 | **Phase 2 — Partner Preview Sessions** | Partner runs representative use cases from each disease area on BioMate: mRNA design for a target variant, docking screen against a known target, pharmacophore filtering, ADMET profiling. BioMate records workflow quality and time-to-result for each session. Target: 6–8 sessions across 5 days. | ~1 hr/day |
| 7–9 | **Phase 3 — QC Defensibility Review** | Partner reviews results from Phase 2. Rates each session on a five-point scale (1 = not usable, 5 = publication-ready). Notes concordance with any prior computational or experimental results for the same targets. Exit survey completed Day 9. | ~2 hrs total |
| 10 | **Debrief + Go/No-Go** | BioMate presents KPI actuals vs. targets (H1: workflow quality ≥ 80%; H2: time-to-result ≤ 30 min; H3: QC defensibility ≥ 70%). Joint go/no-go decision. Phase 1 (full research) scope and checkpoints agreed if GO. | 1–2 hrs |

**Go/No-Go criteria:**

| Decision | Condition |
|---|---|
| GO | All three H1/H2/H3 thresholds met; Phase 1 research begins immediately |
| CONDITIONAL GO | ≥ 2 of 3 met; specific improvements agreed before Month 1 begins |
| NO-GO | < 2 met; collaboration paused pending platform changes |

---

### Full Research Timeline (Post-Pilot)

After a GO decision on Day 10, the research programme follows this timeline. The full pipeline from first partner data to human response prediction takes 2–4 months per disease area.

```
Phase 1 (Months 1–5): Partner studies on validated targets

  [Infectious Disease — Arm 1A: mRNA]
  Spike sequence → codon optimise → 5'/3' UTR design → LNP parameters
  → Predicted expression + immunogenicity → wet lab transfection → compare
  
  [Infectious Disease — Arm 1B: Mpro small molecule]
  PDB 7RFS + 8DZ3 (E166V) → resistance-robust pharmacophore → virtual screen →
  ADMET filter → MD 100 ns → REINVENT4 (2–3 rounds with partner IC50) →
  PKPD → viral dynamics model → predicted clearance time

  [Obesity — Arm 2A: GLP-1R small molecule]
  PDB 7KI0 → TM site pharmacophore → virtual screen →
  ADMET filter → MD 100 ns → REINVENT4 (2–3 rounds with partner EC50) →
  PKPD → body weight model → predicted 12-week weight loss

  [Cancer — Arm 3A: EGFR allosteric]
  PDB 5D41 (EAI045 analogue) → allosteric pharmacophore → virtual screen →
  resistance mutation screen (C797S) → MD → REINVENT4 →
  PKPD → TGI model → predicted time to progression

Phase 2 (Months 6–12): Novel research with partner's own cryo-EM data
  Arm 2B: GLP-1R + BioMate-designed compound → new cryo-EM structure
  Arm 3B: Full-length EGFR nanodisc → first full-length membrane cryo-EM structure
```

---

## Wet Lab Feedback Loop — Unified Architecture

All four arms share the same feedback loop structure. The partner delivers wet lab data at defined checkpoints; BioMate returns updated models and next-round designs within 48 hours.

| Checkpoint | Month | Partner Delivers | BioMate Returns |
|---|---|---|---|
| 1 | Day 10 / Month 1 | Pilot go/no-go; confirm target structures agreed | P0 validation report; Phase 1 design packages |
| 2 | 2 | Arm 1A: mRNA expression (Western blot bands) | Updated mRNA design; LNP optimisation |
| 3 | 2 | Arm 1B: Mpro IC50 for Round 1 compounds (5 total) | REINVENT4 Round 2 designs + retrosynthesis |
| 4 | 3 | Arm 2A: GLP-1R EC50 for Round 1 compounds (5 total) | REINVENT4 Round 2 designs |
| 5 | 3 | Arm 3A: EGFR kinase IC50 (WT, double, triple mutant) for 5 compounds | REINVENT4 Round 2 designs + C797S specificity analysis |
| 6 | 4 | Arm 1B: Mpro Round 2 IC50; in vitro ADME for top 3 | PKPD model + viral clearance prediction |
| 7 | 4 | Arm 2A: GLP-1R Round 2 EC50; Caco-2 Papp for top 3 | Oral bioavailability prediction; body weight model |
| 8 | 5 | Arm 3A: EGFR Round 2 IC50; cellular antiproliferative assay | TGI model; predicted time to progression |
| 9 | 5 | Rodent PK for top compound in each disease area (optional) | Calibrated human PK; final safety margin report |

---

## Deliverables by Phase

**Pilot (Day 2 + Day 10):**
- Day 2: P0 validation report — quantitative pass/fail on all 5 checks against published gold standards
- Day 10: KPI dashboard (H1/H2/H3 actuals vs. targets); go/no-go recommendation; Phase 1 scope agreement if GO

**Phase 1 (Month 5):**
- Virtual screen results for all three disease areas (ranked compound lists with ADMET, docking, MD data)
- DMTA loop summary: IC50 trajectory across 2–3 rounds per disease area
- Human response predictions: viral clearance timeline (Arm 1B), body weight loss at 12 weeks (Arm 2A), predicted time to progression (Arm 3A)
- mRNA design package: optimised sequences, predicted expression metrics, LNP parameters

**Phase 2 (Month 12):**
- New cryo-EM structure(s) from partner's samples (if applicable)
- Complete translational package for top 2 compounds per disease area (suitable as IND-enabling computational package)
- Benchmark concordance table: predicted vs. observed at every stage
- Manuscript draft

---

## Publications

**Paper 1 (Phase 1, Month 6):** Methods paper evaluating BioMate's cryo-EM-to-human-response pipeline against gold standard targets in three disease areas. Target: *Nature Methods* or *Journal of Chemical Information and Modeling*.

**Paper 2 (Phase 2, Month 12):** Scientific discovery paper on the most significant novel finding from Phase 2 (e.g., first BioMate-designed compound with activity against EGFR triple mutant; first cryo-EM structure of BioMate-identified GLP-1R small molecule agonist). Target: *Nature Chemical Biology*, *JACS*, or *Structure*.

---

*April 2026 · BioMate AI · Companion study to the Extended Drug Discovery Study Proposal*
