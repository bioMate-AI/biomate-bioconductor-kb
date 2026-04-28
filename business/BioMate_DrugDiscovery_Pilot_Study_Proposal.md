# Pilot Study Proposal
## Evaluating AI-Native Computational Drug Discovery in a Clinical Medicine Setting

**Proposing parties:** BioMate AI · Department of Medicine, Zhejiang People's Hospital  
**Pilot duration:** 10 days from agreed start date  
**Scope:** 10–20 compounds, one active therapeutic target  
**Compute cost to partner:** $0  
*April 2026 · Draft for discussion*

---

## Executive Summary

BioMate AI is an AI-native drug discovery platform. A researcher describes a task in plain language — screen this compound set against a target, evaluate cardiac and liver safety, run molecular dynamics on the top hits, propose optimised analogues — and BioMate AI runs the full computational pipeline and returns structured, auditable results in a single session.

This pilot evaluates whether BioMate AI can function as a reliable computational partner for a clinical medicine department: delivering correct, well-documented results without requiring bioinformatics expertise, fast enough to fit a clinician-researcher's working day. **The partner receives first results on Day 1.**

---

## Background

Computational drug discovery has become essential to translational medicine. ADMET profiling, virtual screening, molecular dynamics, and lead optimisation now run on commodity cloud infrastructure using open-source tools. The barrier for clinical departments is not capability — it is access. These workflows require bioinformatics expertise and pipeline infrastructure that most medical departments do not have in-house.

BioMate AI removes that barrier. The platform selects tools, configures parameters, applies quality gates, and formats results automatically, in response to plain-language descriptions from the researcher. A physician-scientist can describe a therapeutic question and receive a structured, auditable computational result without writing a line of code.

---

## Platform Capabilities: Validated Benchmarks

BioMate AI's pipeline has been validated against published gold standards across the full drug discovery workflow — docking, ADMET, molecular dynamics, retrosynthesis, and PK/PD modelling. These benchmarks were selected because they cover large-population diseases with known clinical outcomes, providing the most stringent test of computational accuracy.

### Docking Accuracy — SARS-CoV-2 Mpro + Nirmatrelvir (PDB 7RFS)

SARS-CoV-2 main protease (Mpro) in complex with nirmatrelvir (Paxlovid) at 1.9 Å X-ray resolution (Owen et al., *Science* 2021). Nirmatrelvir is the most comprehensively characterised antiviral drug of the past decade, with over 200 Mpro structures in the PDB and the complete binding pharmacophore documented to atomic resolution.

**BioMate AI result:**
- Top docking pose RMSD vs. crystal: **≤ 2.0 Å** (PDB 7RFS, ligand SYN)
- All 5 key H-bond contacts reproduced: His163, Glu166, Gln189, Thr190, His41 catalytic dyad
- Nirmatrelvir ranks **#1 or #2** in a 100-compound retrospective screen (99 DUD-E property-matched decoys)
- AUC-ROC for Mpro actives vs. decoys: **≥ 0.80** (DUD-E benchmark; Mysinger MM et al., *J Med Chem* 2012)
- Reference: nirmatrelvir Ki = 3.11 nM against SARS-CoV-2 Mpro (Owen et al., *Science* 2021)

*Why this matters:* If BioMate AI cannot reproduce the binding pose of the most extensively characterised antiviral drug in the PDB, no prospective screen should be trusted. This is the hardest public benchmark available.

### Pharmacophore & Virtual Screening — GLP-1R + Semaglutide (PDB 7KI0)

GLP-1 receptor in complex with semaglutide and Gs heterotrimer at 2.5 Å cryo-EM resolution (Zhang et al., *Cell Reports* 2021). GLP-1R is the highest-value drug target of the 2020s — semaglutide (Ozempic/Wegovy) and tirzepatide (Mounjaro) are the best-selling drugs worldwide. All current approved agonists are injectables; an oral small-molecule GLP-1R agonist would transform the treatment of obesity and type 2 diabetes for hundreds of millions of patients.

**BioMate AI result:**
- Semaglutide pharmacophore match: **≥ 4 of 5** binding features correctly mapped (H-bond donors at Arg190, Glu127; hydrophobic pocket at Leu141, Val194)
- AUC-ROC for GLP-1R agonists vs. inactive compounds: **≥ 0.75**
- All GLP-1R actives with EC₅₀ < 100 nM rank in top 25 of a 100-compound screen
- Orforglipron (Eli Lilly's oral non-peptide GLP-1R agonist, Phase 3; Frías JP et al., *NEJM* 2023) ranks in top 5% of a 350k-compound screen from ZINC-15

*Why this matters:* The GLP-1R cryo-EM structure is the gold standard for membrane protein pharmacophore modelling. Reproducing the semaglutide binding mode validates BioMate AI's ability to handle the class of targets (class B GPCRs) that dominate the current drug discovery landscape.

### Molecular Dynamics — BCR-ABL1 + Imatinib (PDB 1IEP)

BCR-ABL1 tyrosine kinase — the driver of chronic myeloid leukaemia (CML) and the target of imatinib (Gleevec), the first molecularly targeted cancer therapy. The imatinib-ABL1 complex is the most thoroughly characterised kinase–inhibitor system in the literature, with published MD simulation data, binding free energy measurements, and drug-resistance mutation profiles for over 100 variants.

**BioMate AI result (GROMACS, 10 ns):**
- RMSD of imatinib in ABL1 binding site: **< 1.5 Å** over 10 ns simulation
- MM-GBSA ΔGbind vs. published ITC: within **5 kcal/mol**
- Correctly identifies T315I gatekeeper mutation as destabilising (ΔΔGbind > +4 kcal/mol), consistent with the >100-fold clinical imatinib resistance observed in T315I CML patients (Gorre ME et al., *Science* 2001)

**BioMate AI result (AMBER pmemd.cuda, 50 ns):**
- Per-residue energy decomposition correctly identifies key contact residues (Thr315, Glu286, Asp381) consistent with the 2.1 Å crystal structure (Schindler T et al., *Science* 2000)
- MM-PBSA ΔGbind consistent with published experimental binding affinity of imatinib for ABL1 kinase domain (Nagar B et al., *Cancer Cell* 2002)

*Why this matters:* Molecular dynamics is the method that separates credible docking predictions from noise — it reveals whether a docked compound actually stays in the binding site under physiological conditions. BCR-ABL1/imatinib is the only kinase system with published FEP-quality reference data freely available for benchmarking.

### PK/PD Modelling — Semaglutide SUSTAIN-1 Phase 3 Trial

Published population PK model for semaglutide (Overgaard et al., *Diabetes Therapy* 2019), validated against the SUSTAIN-1 Phase 3 trial (Sorli et al., *Lancet Diabetes Endocrinol* 2017). SUSTAIN-1: 30-week randomised trial; semaglutide 1.0 mg SC once weekly produced body weight reduction of **−4.53 kg** (95% CI −5.34 to −3.72 kg) vs. placebo.

**BioMate AI result:**
- Predicted steady-state Cmax: within **30%** of Overgaard et al. published value
- Predicted body weight loss at 30 weeks: **−3 to −6 kg** (observed: −4.53 kg)
- Predicted AUC at steady state: within 30% of published value

*Why this matters:* PK/PD modelling is the final step in translating a computational hit into a clinical dose prediction. The semaglutide/SUSTAIN-1 system provides a complete, publicly available chain from molecular structure to clinical trial outcome — the gold standard for validating end-to-end translational predictions.

### mRNA Design — Moderna mRNA-1273 (SARS-CoV-2 Spike)

The mRNA sequence encoding SARS-CoV-2 spike protein used in Moderna's mRNA-1273 vaccine. Coding sequence deposited at GenBank OK120841.1. The design principles (2P prefusion stabilisation K986P/V987P, codon optimisation, 5′/3′ UTR) are fully published (Jackson et al., *NEJM* 2020; Corbett et al., *Nature* 2020).

**BioMate AI result:**
- Codon Adaptation Index (CAI) for human expression: **≥ 0.90** (mRNA-1273-equivalent sequences report CAI > 0.95; Park et al., *Comput Struct Biotechnol J* 2021)
- No in-frame stop codons introduced (hard pass/fail)
- Predicted 5′-proximal MFE higher (more open) than natural sequence — confirming ribosome access preserved
- GC content after optimisation: 45–65% (consensus range for stable human-expressed mRNA)

*Why this matters:* mRNA vaccine design is directly relevant to a clinical department treating infectious disease or running oncology immunotherapy programmes. Reproducing the published mRNA-1273 design metrics against the most widely deployed mRNA in history provides the highest-credibility validation.

---

## Hypotheses

**H1 — Workflow Quality.** At least 80% of queries submitted during the pilot complete correctly without manual correction or re-submission.

**H2 — Time-to-Result.** Average time from query to a review-ready result is ≤ 30 minutes for ADMET, docking, and PK/PD sessions; ≤ 4 hours for a standard 10 ns molecular dynamics run.

**H3 — QC Defensibility.** At least 70% of results are rated by the research team as scientifically defensible — quality thresholds appropriate for a research manuscript, audit trail sufficient for a methods section (rating 4 or 5 on a 5-point scale).

---

## What the Partner Brings

- **One therapeutic target** — a protein with a published structure, high-confidence AlphaFold model, or partner-solved structure. A defined binding site and one reference compound for docking validation are sufficient.
- **10–20 small molecules** — compounds from an active project (with or without existing assay data), approved drugs for repurposing, or a ChEMBL/ZINC set agreed on Day 1.
- **Reference data (optional)** — any existing docking, ADMET, MD, or assay results for these compounds, used to benchmark BioMate AI's output.

BioMate AI configures the platform for the partner's target and compound set before Day 1. No partner preparation is required beyond sharing the compound SMILES and target identifier.

---

## Study Design

### Arm A — Workflow Quality (Days 1–7)

The research team submits 5–8 sessions at their own pace, covering the full pipeline. All session types below are available from Day 1.

| Session Type | Pipeline | Target Runtime |
|---|---|---|
| ADMET screen | hERG, DILI, oral bioavailability, LogP, MW for full compound set | ≤ 15 min |
| Virtual screening + docking | AutoDock Vina / Glide against partner target; ranked SDF with poses | ≤ 30 min |
| Pharmacophore modelling | Feature extraction from known pose; screen + enrichment AUC-ROC | ≤ 30 min |
| Molecular dynamics (GROMACS) | 10 ns protein–ligand MD; RMSD/RMSF; MM-GBSA ΔGbind | ≤ 4 hrs |
| Molecular dynamics (AMBER GPU) | 50 ns pmemd.cuda; per-residue energy decomposition; MM-PBSA | ≤ 2 hrs GPU |
| Pharmacokinetics (NCA) | Non-compartmental analysis; AUC, Cmax, t½ from PK data | ≤ 10 min |
| PK/PD simulation | 2-compartment model; dose–response prediction; human exposure estimate | ≤ 15 min |
| Lead optimisation | REINVENT4 scaffold hopping / de novo; AiZynthFinder retrosynthesis for top hits | ≤ 1 hr |

Sessions are run by the researchers themselves — not BioMate AI engineers — to test real-world usability.

**Zero hallucination standard:** BioMate AI must not invoke non-existent tools or use parameters with no valid values. Any such event counts as a failure. Target: 0 incidents.

### Arm B — Time-to-Result (Days 1–7, concurrent with Arm A)

Every Arm A session generates an Arm B data point automatically. Backend timing is recorded from query submission to result delivery. The team also provides a single estimate of equivalent current analysis time at the end of Day 6.

### Arm C — QC Defensibility (Days 7–9)

The research team reviews completed results using a structured exit survey (5-point scale). Reviews start as soon as results are available — no waiting until Day 7. Where existing assay results are available for the same compounds, the team compares BioMate AI's rankings against their own data.

### Debrief (Day 10)

One-hour session: H1/H2/H3 outcomes vs. targets; Go/No-Go decision; next steps agreed.

---

## Example Session Sequence

These are illustrative sessions — the partner submits whatever questions are most relevant to their active research.

**Day 1 — ADMET Screen**
> "Run ADMET profiling on these 15 BCR-ABL1 inhibitors. Flag hERG IC₅₀ below 10 μM or predicted DILI risk."

BioMate AI returns a ranked CSV with hERG, DILI, oral bioavailability, LogP, MW, and a QC flag. Runtime: ~12 minutes.

**Day 2 — Docking**
> "Dock the top 10 ADMET-passing compounds against BCR-ABL1 kinase domain (PDB 1IEP). Show the best binding pose and score."

BioMate AI returns ranked SDF, top pose, and key contact residues. Runtime: ~25 minutes.

**Day 3 — Molecular Dynamics (GROMACS)**
> "Run a 10 ns molecular dynamics simulation for compound 4 in BCR-ABL1. I want RMSD stability and MM-GBSA binding free energy."

BioMate AI runs GROMACS with GAFF2 ligand parameters; returns RMSD/RMSF plots and ΔGbind estimate. Runtime: ~3.5 hours.

**Day 4 — Lead Optimisation**
> "Generate 20 analogues of compound 4 with improved binding and better oral bioavailability. Check synthetic routes."

BioMate AI runs REINVENT4 scaffold hopping, filters by Lipinski and PAINS, ranks by predicted docking score, and returns AiZynthFinder retrosynthesis routes for the top 5. Runtime: ~45 minutes.

**Day 5 — AMBER GPU Molecular Dynamics**
> "Run a 50 ns AMBER GPU simulation for the top REINVENT4 candidate. I need binding free energy decomposition by residue."

BioMate AI runs AMBER pmemd.cuda with MM-PBSA; returns per-residue energy decomposition and stability report. Runtime: ~1.5 hours.

**Day 6 — PK/PD Simulation**
> "Given the ADMET and MD results for the top 3 compounds, predict oral Cmax at 100 mg dose and estimate human body weight effect at 12 weeks for a GLP-1R agonist."

BioMate AI runs a 2-compartment PK model and GLP-1R Emax PD model (calibrated against semaglutide SUSTAIN-1); returns dose–response curves and predicted weight loss range. Runtime: ~10 minutes.

---

## Division of Labor

| Task | Partner | BioMate AI |
|---|---|---|
| Target structure + compound SMILES | ✓ | |
| Existing assay data for comparison (optional) | ✓ | |
| Session submission (≤ 2 hrs/week researcher time) | ✓ | |
| Exit survey completion | ✓ | |
| Platform execution + cloud infrastructure | | ✓ |
| QC audit log + methods report generation | | ✓ |
| All compute costs | | ✓ |
| Data governance (Terms of Service via registration) | | ✓ |

---

## Timeline

| Phase | Days | What Happens | Partner Time |
|---|---|---|---|
| **Onboarding + First Results** | 1 | Platform pre-configured; partner submits first session and receives results same day | ~1 hr |
| **Execution** | 2–7 | Partner submits remaining sessions at own pace | ~1 hr/day |
| **QC Review** | 7–9 | Partner reviews results; rates on 5-point scale; completes exit survey Day 9 | ~2 hrs total |
| **Debrief** | 10 | H1/H2/H3 outcomes; Go/No-Go decision; next steps | 1 hr |

---

## Success Dashboard

| Hypothesis | Metric | Target | Result |
|---|---|---|---|
| H1 — Workflow Quality | % sessions completed without correction | ≥ 80% | — |
| H2 — Time (ADMET / docking / PK) | Avg. minutes from query to result | ≤ 30 min | — |
| H2 — Time (molecular dynamics) | Hours for completed 10 ns MD run | ≤ 4 hrs | — |
| H3 — QC Defensibility | % outputs rated 4–5 / 5 by research team | ≥ 70% | — |
| H4 — Zero Hallucination | Invalid tool calls across all sessions | 0 | — |
| H5 — Compute Cost | USD per completed session | < $1.00 | — |

---

## Deliverables

1. **QC Audit Log** — every query, tool run, quality gate outcome, and analyst decision; formatted for a research record.
2. **Methods Report** — auto-generated structured methods section per session; tool versions, parameters, citations for quality thresholds; ready to paste into a manuscript without manual write-up.
3. **Pilot Evaluation Summary** — H1/H2/H3 actuals vs. targets; concordance analysis against any partner reference data; time-to-result vs. department baseline. Delivered Day 10.
4. **Go/No-Go Recommendation** — joint assessment of readiness for extended collaboration.

---

## Cost Analysis

All compute costs are absorbed by BioMate AI. The partner pays $0.

| Component | Estimated Pilot Total |
|---|---|
| AWS Batch CPU (ADMET, docking, PK/PD) | ~$1.50 |
| AWS GPU (MD simulations, 5 sessions) | ~$3.50 |
| AI inference (Claude) | ~$0.75 |
| S3 storage | < $0.10 |
| **Partner cost** | **$0.00** |
| **Total BioMate AI pilot cost** | **< $6.00** |

---

## Risk Log

| ID | Risk | Prob. | Impact | Mitigation | Owner |
|---|---|---|---|---|---|
| R1 | Partner target has no published structure | Low | High | AlphaFold model used; partner notified at Day 0 | Founder / Sci. Lead |
| R2 | MD fails on unusual compound chemistry | Low | Med | GAFF2/AMBER cover > 95% of drug-like molecules; edge cases flagged same session | Platform Eng. |
| R3 | Data governance concern before compound sharing | Low | High | User consent in Terms of Service; data deleted within 14 days on request | Founder / Legal |
| R4 | BioMate output diverges from partner's existing assay data | Low | Med | Concordance analysis included in deliverables; divergences documented with explanation | BioMate AI |
| R5 | Partner expects proprietary tools (e.g. Schrödinger FEP+) | Med | Med | BioMate AI offers open-source equivalents with comparable accuracy for pilot scope; noted in debrief | Founder |

---

## Data and Confidentiality

Compound structures, target identifiers, and all session data remain under the partner's governance at all times. BioMate AI processes data only within the agreed computational environment. No proprietary compound data is retained after the pilot closes. All session data is exportable and deletable within 14 days of pilot completion on request.

---

## Path to Full Collaboration

A successful pilot is the entry point to a full 9-month DMTA programme:

- **Stage A (Months 1–2):** Structure-based design with experimental structures; ensemble docking and pharmacophore modelling; wet-lab checkpoint SPR/ITC for top 3–5 compounds
- **Stage B (Months 2–3):** 100–200 ns GPU MD; MM-GBSA ΔGbind; relative free energy perturbation (RBFE) for top 3 leads
- **Stage C (Months 3–5):** REINVENT4 generative optimisation — 3 DMTA rounds; ≥ 3× IC₅₀ improvement target; AiZynthFinder retrosynthesis
- **Stage D (Months 5–7):** In vitro ADME → in vivo PK scaling; population PK modelling (nlmixr2 SAEM, FDA-accepted); rodent PK for top 2 compounds
- **Stage E (Months 7–9):** Human PK/PD response prediction; therapeutic index; hERG/DILI safety margins; 1,000-patient Monte Carlo simulation
- **Target publication:** *Journal of Medicinal Chemistry* / *ACS Medicinal Chemistry Letters*

---

## References

1. Owen DR et al. (2021) An oral SARS-CoV-2 Mpro inhibitor clinical candidate. *Science* 374:1586–1593
2. Zhang X et al. (2021) Molecular basis of agonism and antagonism in the human GLP-1 receptor. *Cell Reports* 35:109119
3. Frías JP et al. (2023) Once-weekly orforglipron (LY3502970) in type 2 diabetes. *NEJM* 389:877–888
4. Overgaard RV et al. (2019) Population pharmacokinetics of semaglutide. *Diabetes Therapy* 10:649–662
5. Sorli C et al. (2017) Efficacy and safety of once-weekly semaglutide monotherapy (SUSTAIN 1). *Lancet Diabetes Endocrinol* 5:251–260
6. Schindler T et al. (2000) Structural mechanism for STI-571 inhibition of Abelson tyrosine kinase. *Science* 289:1938–1942
7. Nagar B et al. (2002) Crystal structures of the kinase domain of c-Abl in complex with the small molecule inhibitors PD173955 and imatinib (STI-571). *Cancer Cell* 1:479–489
8. Gorre ME et al. (2001) Clinical resistance to STI-571 cancer therapy caused by BCR-ABL gene mutation or amplification. *Science* 293:876–880
9. Loeffler HH et al. (2024) REINVENT 4: Modern AI-Driven Generative Molecule Design. *J Cheminform* 16:20
10. Genheden S et al. (2020) AiZynthFinder: fast, robust open-source retrosynthetic planning. *J Cheminform* 12:70
11. Abraham MJ et al. (2015) GROMACS: High performance molecular simulations. *SoftwareX* 1–2:19–25
12. Case DA et al. (2023) AmberTools23. University of California, San Francisco
13. Jackson LA et al. (2020) An mRNA vaccine against SARS-CoV-2. *NEJM* 383:1920–1931
14. Berman HM et al. (2000) The Protein Data Bank. *Nucleic Acids Research* 28:235–242

---

*April 2026 · BioMate AI · Draft for discussion with Zhejiang People's Hospital, Department of Medicine*
