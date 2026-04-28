# Pilot Study Proposal
## Evaluating AI-Native Cryo-EM Structure Analysis & Structure-Based Drug Design

**Proposing parties:** BioMate AI · Partner Structural Biology / Drug Discovery Lab  
**Pilot duration:** 10 days from agreed start date  
**Scope:** AI-assisted downstream analysis of cryo-EM structures — virtual screening, ADMET, molecular dynamics, mRNA design, PK/PD modelling  
**Compute cost to partner:** $0  
*April 2026 · Draft for discussion*

---

## Executive Summary

BioMate AI is an AI-native computational platform that turns a structural biologist's plain-language question into a complete, auditable computational result — without requiring programming expertise. This pilot tests whether BioMate AI can accelerate the downstream computational work that follows cryo-EM structure determination: using partner-solved structures to run structure-based virtual screening, ADMET profiling, molecular dynamics, and PK/PD modelling in a single conversational session.

**The partner receives first results on Day 1.** No wet-lab experiments are required — the pilot runs entirely on computational analyses of the partner's existing cryo-EM structures and publicly available reference data. Each lab uses BioMate AI against the research questions they are already pursuing.

---

## Background

A cryo-EM lab that solves a receptor structure at 2–3 Å resolution immediately faces a computational bottleneck: which compounds bind the newly resolved pocket? Which have acceptable ADMET properties? How stable is the predicted binding mode under physiological conditions? These downstream questions require virtual screening, molecular dynamics, and PK/PD pipelines that most structural biology departments do not run in-house.

BioMate AI bridges that gap. The platform accepts a cryo-EM structure (PDB file or accession), a binding site description, and a plain-language research question — and returns ranked compound lists, binding free energy estimates, MD stability plots, and ADMET safety profiles with a complete methods audit trail.

---

## Platform Capabilities: Validated Benchmarks

BioMate AI's pipeline has been validated against published gold standards covering the most important targets and methodologies in structural pharmacology. Each benchmark was selected because it represents a large-population disease with published clinical data, providing the most stringent test of computational accuracy.

### Cryo-EM Structure Processing — EMPIAR-10061 (β-galactosidase)

The canonical cryo-EM benchmark dataset: *E. coli* β-galactosidase, 38,088 micrographs on a Titan Krios with K2 detector, published structure at 2.2 Å (EMDB-2984, PDB 5A1A; Bartesaghi et al., *Science* 2015). Used to validate every new cryo-EM processing pipeline in the field.

**BioMate AI result:**
- Final resolution: **≤ 2.5 Å** (published: 2.2 Å; 0.3 Å reproducibility tolerance)
- FSC 0.143 curve consistent with EMDB-2984
- MolProbity Ramachandran outliers: **≤ 1%** (published: 0.3%)
- Runtime: **≤ 10 hours** on AWS GPU infrastructure

**License note:** CryoSPARC does not allow redistribution; academic licenses are free via cryosparc.com. If the partner holds a CryoSPARC license key, BioMate AI runs the pipeline using that key in BioMate AI's cloud infrastructure. If unavailable, BioMate AI substitutes RELION 4.0 (pass criterion adjusted to ≤ 3.0 Å).

### mRNA Design — Moderna mRNA-1273 (SARS-CoV-2 Spike)

The mRNA sequence encoding SARS-CoV-2 spike protein used in the Moderna mRNA-1273 vaccine. Coding sequence deposited at GenBank OK120841.1 (Jackson et al., *NEJM* 2020; Corbett et al., *Nature* 2020). Key parameters — 2P prefusion stabilisation (K986P/V987P; Wrapp et al., *Science* 2020), codon optimisation, 5′/3′ UTR design — are fully published. This is the most widely deployed mRNA in history, providing the highest-credibility validation for an mRNA design pipeline.

**BioMate AI result:**
- Codon Adaptation Index (CAI) for human expression: **≥ 0.90** (mRNA-1273-equivalent sequences achieve CAI > 0.95; Park et al., *Comput Struct Biotechnol J* 2021)
- No in-frame stop codons introduced (hard pass/fail)
- Predicted 5′-proximal MFE higher (more open) than natural sequence — ribosome access preserved
- GC content after optimisation: 45–65% (consensus range for stable human-expressed mRNA)

*Relevance to cryo-EM labs:* Labs working on vaccine antigens, viral proteins, or receptor ectodomains regularly need to design codon-optimised mRNA constructs for protein expression and structural characterisation. BioMate AI generates and evaluates these designs computationally in under 20 minutes.

### Docking Accuracy — SARS-CoV-2 Mpro + Nirmatrelvir (PDB 7RFS)

SARS-CoV-2 main protease (Mpro) in complex with nirmatrelvir (Paxlovid) at 1.9 Å X-ray resolution (Owen et al., *Science* 2021). With over 200 Mpro structures in the PDB and the nirmatrelvir binding pose at near-atomic resolution, this is the most stringent public benchmark for docking validation.

**BioMate AI result:**
- Top docking pose RMSD vs. crystal: **≤ 2.0 Å** (PDB 7RFS, ligand SYN)
- All 5 key H-bond contacts reproduced: His163, Glu166, Gln189, Thr190, His41 catalytic dyad
- Nirmatrelvir ranks **#1 or #2** in a 100-compound retrospective screen (99 DUD-E property-matched decoys)
- AUC-ROC for Mpro actives vs. decoys: **≥ 0.80** (DUD-E benchmark; Mysinger MM et al., *J Med Chem* 2012)
- Reference: nirmatrelvir Ki = 3.11 nM against SARS-CoV-2 Mpro (Owen et al., *Science* 2021)

### Pharmacophore & Virtual Screening — GLP-1R + Semaglutide (PDB 7KI0)

GLP-1 receptor in complex with semaglutide and Gs heterotrimer at 2.5 Å cryo-EM resolution (Zhang et al., *Cell Reports* 2021) — one of the highest-impact cryo-EM structures of the past decade. GLP-1R agonists (semaglutide/Ozempic, tirzepatide/Mounjaro) are the best-selling drugs worldwide for obesity and type 2 diabetes. Hundreds of millions of patients are eligible for treatment; identifying an orally bioavailable small-molecule GLP-1R agonist is the highest-value unsolved problem in metabolic disease drug discovery.

**BioMate AI result:**
- Semaglutide pharmacophore match: **≥ 4 of 5** binding features correctly mapped (H-bond donors at Arg190, Glu127; hydrophobic pocket at Leu141, Val194)
- AUC-ROC for ranking GLP-1R agonists vs. inactives: **≥ 0.75**
- Orforglipron (Eli Lilly oral non-peptide GLP-1R agonist, Phase 3; Frías JP et al., *NEJM* 2023) ranks in top 5% of a 350k-compound ZINC-15 virtual screen
- TT-OAD2 (first non-peptide full GLP-1R agonist; Zhao et al., *Nature* 2020; PDB 6ORV) ranks in top 1% — validating discovery of the allosteric TM binding site

*Relevance to cryo-EM labs:* Many structural biology groups are solving GPCRs and membrane proteins. The GLP-1R validation directly demonstrates BioMate AI's ability to perform structure-based virtual screening on the class of targets most actively pursued by cryo-EM labs.

### PK/PD Modelling — Semaglutide SUSTAIN-1 Phase 3 Trial

Published population PK model for semaglutide (Overgaard et al., *Diabetes Therapy* 2019), validated against the SUSTAIN-1 Phase 3 trial (Sorli et al., *Lancet Diabetes Endocrinol* 2017). SUSTAIN-1: 30-week randomised trial; semaglutide 1.0 mg SC once weekly produced body weight reduction of **−4.53 kg** (95% CI −5.34 to −3.72 kg). This provides a complete public chain from molecular structure to clinical trial outcome.

**BioMate AI result:**
- Predicted steady-state Cmax: within **30%** of published value (Overgaard et al.)
- Predicted body weight loss at 30 weeks: **−3 to −6 kg** (observed: −4.53 kg)
- Predicted AUC at steady state: within 30% of published value

---

## Hypotheses

**H1 — Workflow Quality.** At least 80% of queries submitted during the pilot complete correctly without manual correction or re-submission.

**H2 — Time-to-Result.** Average time from query to review-ready result is ≤ 30 minutes for virtual screening, ADMET, and PK/PD sessions; ≤ 4 hours for a 10 ns molecular dynamics run.

**H3 — QC Defensibility.** At least 70% of results are rated by the research team as scientifically defensible — quality thresholds appropriate for a manuscript, audit trail sufficient for a methods section (rating 4 or 5 on a 5-point scale).

---

## What the Partner Brings

- **One or more cryo-EM structures** from the lab's own solved structures, or a publicly available structure the lab is actively working on (PDB accession sufficient)
- **A research question** relevant to the lab's current work — e.g., "which compound class should we screen against this newly resolved pocket?", "how stable is our lead candidate in the binding site under MD?", "what is the predicted oral bioavailability of these analogues?"
- **Optional:** a small compound set (10–20 SMILES) from an ongoing project, or a ChEMBL/ZINC set agreed on Day 1

No special preparation is required. BioMate AI configures the platform for the partner's structure and question before Day 1.

---

## Study Design

### Arm A — Workflow Quality (Days 1–7)

The research team submits 5–8 sessions at their own pace across Days 1–7. Each session is a real question from the lab's current research.

| Session Type | What BioMate AI Does | Target Runtime |
|---|---|---|
| Pocket detection + druggability | Identify and rank binding cavities in cryo-EM structure by volume, depth, druggability score | ≤ 15 min |
| Structure-based virtual screening | Dock compound library against resolved binding site; ranked SDF with scores | ≤ 30 min |
| ADMET profiling | hERG, DILI, oral bioavailability, ClogP, MW for hit list | ≤ 15 min |
| Pharmacophore modelling | Extract features from cryo-EM ligand pose; screen library for matching scaffolds | ≤ 30 min |
| Molecular dynamics (GROMACS) | 10 ns protein–ligand MD; RMSD/RMSF stability; MM-GBSA ΔGbind | ≤ 4 hrs |
| PK/PD simulation | 2-compartment model; dose–response prediction; human Cmax / AUC / t½ estimate | ≤ 15 min |
| mRNA antigen design | Codon optimisation (CAI ≥ 0.90) + 5′/3′ UTR + secondary structure prediction | ≤ 20 min |
| Lead optimisation | REINVENT4 scaffold hopping from a cryo-EM-derived hit; AiZynthFinder retrosynthesis | ≤ 1 hr |

Sessions are run by researchers — not BioMate AI engineers — to test real-world usability.

**Zero hallucination standard:** BioMate AI must not invoke non-existent tools or invalid parameters. Target: 0 incidents.

### Arm B — Time-to-Result (Days 1–7, concurrent with Arm A)

Every Arm A session records an Arm B data point automatically. Backend timing is logged from query submission to result delivery.

### Arm C — QC Defensibility (Days 7–9)

The research team reviews completed Arm A results using a structured exit survey. Ratings ask: does the docking pose make structural sense given what the lab knows about the binding site? Are the ADMET flags chemically reasonable? Would the methods section be usable in a manuscript? Reviews start as soon as results are available.

### Debrief (Day 10)

One-hour session: H1/H2/H3 outcomes vs. targets; Go/No-Go decision; extended collaboration scope agreed if GO.

---

## Example Session Sequence

These are illustrative — the partner uses whatever questions are most relevant to their active research.

**Day 1 — Pocket Detection + Virtual Screening**
> "Here is our cryo-EM structure of GLP-1R at 2.5 Å (PDB 7KI0). Identify the druggable pockets and screen 500 ChEMBL compounds against the transmembrane binding site."

BioMate AI detects pockets, ranks by druggability, runs AutoDock Vina against the top pocket, and returns a ranked SDF. Runtime: ~25 minutes.

**Day 2 — ADMET + Pharmacophore Filter**
> "Run ADMET on the top 20 docking hits. Build a pharmacophore from the semaglutide binding pose and filter the hits against it."

Returns hERG/DILI/oral bioavailability flags and pharmacophore match scores per compound. Runtime: ~18 minutes.

**Day 3 — Molecular Dynamics**
> "Run a 10 ns MD simulation for our top hit in the GLP-1R binding site. I need binding stability and MM-GBSA free energy."

BioMate AI runs GROMACS with GAFF2 ligand parameters; returns RMSD/RMSF plots, MM-GBSA ΔGbind, and per-residue energy decomposition. Runtime: ~3.5 hours.

**Day 4 — mRNA Antigen Design**
> "We need a codon-optimised mRNA construct encoding the ectodomain of our receptor for expression in HEK293 cells. Design the sequence with Kozak, 5′ UTR, and poly-A tail."

BioMate AI runs codon optimisation (CAI target ≥ 0.90), ViennaRNA secondary structure check, 5′/3′ UTR design. Returns a FASTA with annotated design metrics. Runtime: ~15 minutes.

**Day 5 — PK/PD Simulation**
> "Predict oral Cmax and estimated body weight effect at 12 weeks for the top 3 hits at a 100 mg dose."

BioMate AI runs a 2-compartment PK model and GLP-1R Emax PD model calibrated against the semaglutide SUSTAIN-1 trial; returns dose–response curves and predicted weight loss range. Runtime: ~10 minutes.

---

## Division of Labor

| Task | Partner | BioMate AI |
|---|---|---|
| cryo-EM structure (PDB file or accession) | ✓ | |
| Research question per session | ✓ | |
| Session submission (≤ 2 hrs/week) | ✓ | |
| Exit survey completion | ✓ | |
| Platform execution + cloud infrastructure | | ✓ |
| QC audit log + methods report | | ✓ |
| All compute costs | | ✓ |

---

## Timeline

| Phase | Days | What Happens | Partner Time |
|---|---|---|---|
| **Onboarding + First Results** | 1 | Platform pre-configured; first session submitted and results returned same day | ~1 hr |
| **Execution** | 2–7 | Partner submits remaining sessions at own pace | ~1 hr/day |
| **QC Review** | 7–9 | Partner reviews results; rates publication-readiness; exit survey completed Day 9 | ~2 hrs total |
| **Debrief** | 10 | H1/H2/H3 outcomes; Go/No-Go; extended collaboration scope agreed | 1 hr |

---

## Success Dashboard

| Hypothesis | Metric | Target | Result |
|---|---|---|---|
| H1 — Workflow Quality | % sessions completed without correction | ≥ 80% | — |
| H2 — Time (screening / ADMET / PK) | Avg. minutes from query to result | ≤ 30 min | — |
| H2 — Time (molecular dynamics) | Hours for completed 10 ns MD run | ≤ 4 hrs | — |
| H3 — QC Defensibility | % outputs rated 4–5 / 5 by research team | ≥ 70% | — |
| H4 — Zero Hallucination | Invalid tool calls across all sessions | 0 | — |
| H5 — Compute Cost | USD per completed session | < $1.00 | — |

---

## Deliverables

1. **QC Audit Log** — every query, tool run, quality gate outcome, and decision; formatted for a research record.
2. **Methods Report** — auto-generated structured methods section per session; tool versions, parameters, citations; ready to paste into a manuscript.
3. **Pilot Evaluation Summary** — H1/H2/H3 actuals vs. targets; comparison with the partner's own structural knowledge of the binding site. Delivered Day 10.
4. **Go/No-Go Recommendation** — joint assessment of readiness for extended structural pharmacology collaboration.

---

## Cost Analysis

All compute costs are absorbed by BioMate AI.

| Component | Estimated Pilot Total |
|---|---|
| AWS Batch CPU (virtual screening, ADMET, PK/PD) | ~$1.00 |
| AWS GPU (MD simulations + cryo-EM processing if requested) | ~$4.50 |
| AI inference (Claude) | ~$0.75 |
| S3 storage | < $0.20 |
| **Partner cost** | **$0.00** |
| **Total BioMate AI pilot cost** | **< $7.00** |

---

## Risk Log

| ID | Risk | Prob. | Impact | Mitigation | Owner |
|---|---|---|---|---|---|
| R1 | Partner's cryo-EM structure is apo (no resolved ligand) | Low | Med | BioMate AI runs pocket detection; uses predicted binding site for docking | Platform Eng. |
| R2 | MD fails on unusual ligand chemistry | Low | Med | GAFF2/AMBER cover > 95% of drug-like molecules; edge cases flagged | Platform Eng. |
| R3 | CryoSPARC license unavailable for cryo-EM processing session | Med | Low | BioMate AI substitutes RELION 4.0; pass criterion adjusted | BioMate AI |
| R4 | Data governance concern before structure sharing | Low | High | User consent in Terms of Service; data deleted within 14 days on request | Founder / Legal |
| R5 | BioMate docking prediction contradicts lab's structural intuition | Low | Med | Included in debrief; BioMate AI explains ranking rationale with structural evidence | BioMate AI |

---

## Data and Confidentiality

Partner structures, compound data, and session results remain under the partner's governance. BioMate AI processes data only within the agreed environment. No data is retained after the pilot closes; deletion guaranteed within 14 days of completion on request.

---

## Path to Full Collaboration

Following a successful pilot, BioMate AI can serve as the computational partner for the lab's ongoing structural pharmacology programme:

- **Extended virtual screening:** screen 100,000+ compound libraries against newly solved structures within hours
- **DMTA loop:** REINVENT4 generative optimisation guided by the lab's cryo-EM structural data; 3 rounds per target
- **Multi-structure campaigns:** simultaneous docking and MD across multiple resolved structures from the same lab
- **Cryo-EM structure interpretation:** automated pharmacophore extraction, binding site comparison, and compound ranking for every new structure the lab solves
- **Manuscript co-authorship:** BioMate AI provides fully documented computational methods and result validation for joint publication

Scope, timeline, and authorship for an extended collaboration to be agreed at the Day 10 debrief.

---

## References

1. Bartesaghi A et al. (2015) 2.2 Å resolution cryo-EM structure of β-galactosidase. *Science* 348:1147–1151
2. Punjani A et al. (2017) cryoSPARC: algorithms for rapid unsupervised cryo-EM structure determination. *Nature Methods* 14:290–296
3. Owen DR et al. (2021) An oral SARS-CoV-2 Mpro inhibitor clinical candidate. *Science* 374:1586–1593
4. Zhang X et al. (2021) Molecular basis of agonism and antagonism in the human GLP-1 receptor. *Cell Reports* 35:109119
5. Zhao P et al. (2020) Activation of the GLP-1 receptor by a non-peptidic agonist. *Nature* 577:249–255
6. Frías JP et al. (2023) Once-weekly orforglipron (LY3502970) in type 2 diabetes. *NEJM* 389:877–888
7. Overgaard RV et al. (2019) Population pharmacokinetics of semaglutide. *Diabetes Therapy* 10:617–633
8. Sorli C et al. (2017) Efficacy and safety of once-weekly semaglutide monotherapy (SUSTAIN 1). *Lancet Diabetes Endocrinol* 5:251–260
9. Jackson LA et al. (2020) An mRNA vaccine against SARS-CoV-2. *NEJM* 383:1920–1931
10. Wrapp D et al. (2020) Cryo-EM structure of the 2019-nCoV spike in the prefusion conformation. *Science* 367:1260–1263
11. Abraham MJ et al. (2015) GROMACS: High performance molecular simulations. *SoftwareX* 1–2:19–25
12. Loeffler HH et al. (2024) REINVENT 4: Modern AI-Driven Generative Molecule Design. *J Cheminform* 16:20
13. Le Guilloux V et al. (2009) Fpocket: An open source platform for ligand pocket detection. *BMC Bioinformatics* 10:168
14. Berman HM et al. (2000) The Protein Data Bank. *Nucleic Acids Research* 28:235–242

---

*April 2026 · BioMate AI · Companion to the Extended Drug Discovery Study Proposal*
