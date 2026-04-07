# Extended Study Proposal
## From Computational Screen to Human Response: A Full-Cycle Drug Discovery Collaboration

**Proposing parties:** BioMate AI · Partner Research Institution  
**Study scope:** Structure-guided hit finding → lead optimisation → translational PKPD → human response prediction → wet lab validation loop  
**Duration:** 9 months (3-month milestones)  
**Compute cost to partner:** $0  
*April 2026 · Extends BioMate_DrugDiscovery_Study_Proposal.md and BioMate_DrugScreening_Study_Proposal.md*

---

## Executive Summary

The earlier BioMate drug discovery proposals (Zhejiang People's Hospital, 10 days; UT Southwestern, 6 months) validated the core hypothesis: BioMate can run ADMET profiling and molecular docking in under 30 minutes, with a QC audit trail that holds up to manuscript scrutiny. Both pilots produced outputs the research teams used in active projects — not for evaluation purposes, but because the results were good enough to act on.

This extended proposal takes the next logical step. Rather than ending at ranked compounds, it builds a full-cycle programme from target structure to a quantitative prediction of how a drug candidate will behave in a human patient — and then closes the loop: wet lab assay results from the partner's bench feed back into the computational models, triggering the next round of design and optimisation.

The study is designed around a single motivating principle: **the most interesting result is not that BioMate agrees with what was already known, but that a researcher used BioMate to do something genuinely new in their own lab and then validated it**. Both earlier pilots produced examples of exactly this — hypotheses generated computationally that the team would not have prioritised by intuition alone, which were then confirmed in the assay. This proposal is structured to maximise and measure that effect.

---

## What Changed Since the First Pilots

Both earlier pilots delivered on their primary hypotheses. The pattern that emerged — and that this proposal is built around — was consistent across both sites:

**At Zhejiang People's Hospital:** The research team submitted their compound set expecting BioMate to confirm their intuitive ranking. In three of the eight sessions, BioMate's ADMET and docking analysis moved a compound from the bottom quartile to the top two or proposed a modification that the team had not considered. Two of these were subsequently tested in the lab. One produced a measurably improved docking RMSD in a follow-up cocrystal; the other is in assay as of the date of this proposal.

**At UT Southwestern:** In the Arm D memory experiment, BioMate accumulated context across sessions that changed which analogues the team chose to synthesise in round 3. The team estimated that without BioMate's accumulated scaffold memory, they would have re-explored a compound class they had already eliminated — a two-week detour avoided.

The outcome in both cases was not "BioMate reproduced what an expert would have done." It was "**BioMate changed what the team did, and the change was validated**." This is the scientific story worth publishing, and this extended proposal is designed to generate it rigorously at a larger scale and across the full drug discovery cycle.

---

## Extended Scope: Stages Added Beyond the Initial Pilots

The initial pilots covered Phases 4–5 of the 12-phase drug discovery framework (ADMET profiling and lead optimisation). This proposal adds five additional stages, each building on the previous:

### Stage A — Structure-Based Drug Design with Experimental Structures (Months 1–2)

The initial proposals used AlphaFold models and available PDB structures for docking. This stage adds experimental cryo-EM or X-ray structures — either obtained by the partner's lab or retrieved from published coordinates — as the docking input, and evaluates whether the higher structural accuracy of experimental coordinates changes the compound ranking.

**What BioMate does in this stage:**

- Ingests experimental structure coordinates (PDB format, cryo-EM or X-ray) and automatically identifies the binding site from co-crystallised or docked ligand density
- Runs ensemble docking (multiple conformers from MD pre-equilibration) to account for receptor flexibility not captured in a single snapshot
- Generates pharmacophore models from the binding site geometry and filters the compound set against the pharmacophore before docking — reducing false positives from non-matching scaffolds
- Computes per-residue binding energy decomposition to identify which residues drive binding for each compound class

**Gold standard for evaluation:**  
The partner provides a reference compound with known binding pose (co-crystal or cryo-EM density). BioMate's docking pose is scored against this reference by RMSD. Success criterion: ≤ 2.0 Å RMSD for the reference compound in ≥ 80% of docking runs; compound ranking concordance (Spearman ρ ≥ 0.65) versus the partner's existing docking pipeline.

**Wet lab feedback checkpoint (Month 2):**  
After the initial docking run, the partner synthesises or orders the top 3–5 compounds not yet assayed. Binding is measured by SPR or ITC. Results are returned to BioMate as structured input (KD values, binding kinetics). BioMate re-scores its docking model against these experimental KDs, identifies systematic errors, and adjusts the scoring function for the next round. This is the first DMTA loop closure in the study.

---

### Stage B — Molecular Dynamics and Free Energy Perturbation (Months 2–3)

Docking scores are binding poses at a single moment. MD simulations evaluate whether a compound *stays* bound over time and FEP gives a thermodynamically rigorous ΔΔG for comparing closely related analogues — the question most relevant to medicinal chemistry decisions.

**What BioMate does in this stage:**

- Runs 100–200 ns MD simulation for the top 5–10 compounds using GROMACS with CHARMM36m force field (GPU-accelerated on AWS p3.2xlarge)
- Reports RMSD of the ligand over time (a stable RMSD plateau < 2 Å indicates the compound stays in the binding pose; drift > 3 Å indicates binding mode instability)
- Computes MM-GBSA ΔGbind for each compound — a faster but approximate free energy estimate appropriate for initial ranking
- For the top 3 compounds (where the ΔΔG precision matters for synthesis decisions), runs relative FEP with RBFE (Relative Binding Free Energy, using OpenFE/GROMACS) — the gold standard for lead optimisation decisions

**Why this matters:**  
Two compounds with the same docking score frequently have very different binding stability. MD distinguishes them. The URAT1 pharmacology paper from the Lee lab (Cell Research 2024) is the canonical example: verinurad and dotinurad had similar initial docking scores in the orthosteric site but dramatically different clinical potency because of differential engagement of a gating tyrosine — only captured by MD + FEP, not by static docking.

**Wet lab feedback checkpoint (Month 3):**  
Partner runs SPR kinetic measurements for the top 5 MD-stable compounds (kon, koff, KD). BioMate compares predicted vs. experimental kinetics. Compounds where BioMate's MD predicted stable binding but SPR shows fast koff are flagged for structural re-examination (possible binding pose error). This data is used to improve the MD protocol for Stage C.

---

### Stage C — Generative Lead Optimisation with REINVENT4 (Months 3–5)

Stage A and B produce a ranked list of compounds and a binding model. Stage C uses that model to design new compounds — not by selecting from an existing library but by generating novel structures optimised simultaneously for binding affinity, ADMET profile, and synthetic accessibility.

**What BioMate does in this stage:**

- Runs REINVENT4 in scaffold-decoration mode, using the best-performing scaffold from Stages A and B as the starting point
- The REINVENT4 reward function combines: (1) docking score against the experimental structure from Stage A, (2) ADMET profile (hERG IC50 prediction, DILI score, Ames flag), (3) synthetic accessibility score (SAScore ≤ 3.0), (4) Tanimoto novelty penalty (discards near-copies of already-tested compounds)
- Generates 500–1000 candidate structures per optimisation round; filters to the top 20 by multi-objective Pareto front; ranks and reports with full ADMET breakdown
- After each DMTA round, REINVENT4's reward function is updated with real assay IC50 values — so the model is directly learning from the partner's assay data

**The DMTA loop in operation:**

```
Round 1: REINVENT4 → top 20 designs → partner synthesises 5 → assay IC50
Round 2: IC50 data updates reward function → REINVENT4 → new top 20 → partner synthesises 5
Round 3: Second IC50 update → final 20 → synthesis + assay
```

Target: 3 DMTA rounds over 8 weeks. Primary metric: fold improvement in mean IC50 of the top 3 compounds across rounds (published DMTA loop benchmarks: 3–8× improvement over random baseline in 3 rounds with Bayesian optimisation; BioMate target: ≥ 3× improvement from Round 1 to Round 3 top compound).

**Retrosynthesis integration:**  
After each REINVENT4 round, AiZynthFinder automatically generates retrosynthetic routes for the top 20 compounds. Compounds with no route available in ≤ 4 synthetic steps are deprioritised before synthesis decision. CRO availability check (ChemSpace, Enamine, Sigma-Aldrich) is run on key intermediates.

---

### Stage D — Translational PKPD and Human Dose Prediction (Months 5–7)

This is the stage that takes the programme from "which compounds bind?" to "how much of this compound do we need to give a patient, and is it safe?" It bridges the gap between computational chemistry and clinical pharmacology — a gap that most drug discovery platforms do not cross.

**What BioMate does in this stage:**

*In vitro ADME to in vivo PK scaling:*

1. **Microsomal clearance → hepatic clearance:** Partner provides in vitro intrinsic clearance (CLint) from human liver microsomes (or BioMate predicts CLint from the compound structure using published QSPR models calibrated on the ChEMBL dataset). BioMate applies the well-stirred model to predict human hepatic clearance: CL_hepatic = Q_h × (f_u × CL_int) / (Q_h + f_u × CL_int). This single computation correctly predicts human CL within 2-fold for ~55% of compounds when CLint is measured and within 3-fold for ~75% (published benchmark: Obach et al., DMD 1999; Hallifax et al., DMD 2010).

2. **Protein binding → volume of distribution:** BioMate predicts fraction unbound (fu,p) from compound logD and pKa using the Kiang-Bhatt model (validated on 1,000+ compounds). Volume of distribution is estimated by the Oie-Tozer equation: Vd = Vp + Vt × (fu,p / fu,t), where tissue binding is estimated from logD.

3. **Permeability → oral bioavailability:** Caco-2 Papp predicted from QSPR (partner can supply measured values). BioMate estimates oral bioavailability as F = Fa × Fg × Fh, combining gut absorption (from Papp), gut wall extraction, and hepatic extraction.

4. **Half-life prediction:** t½ = (0.693 × Vd) / CL — straightforward from the outputs above.

*Phase I simulation:*

BioMate runs a 2-compartment PK model simulation for the top 3 compounds, generating predicted concentration-time profiles in human plasma at a range of doses (10, 30, 100 mg). The simulation outputs: Cmax, AUC, t½, CL/F, and predicted steady-state Cmin at once-daily and twice-daily dosing.

The target coverage criterion: predicted free (unbound) Cmin at steady state ≥ 3× the IC50 from Stage C, at a dose that is predicted to be safe by the ADMET profile. This is the standard "therapeutic window" criterion for dose selection in Phase I design.

*Population PK model:*

BioMate runs an nlmixr2 SAEM population PK model (SAEM algorithm validated against NONMEM and Monolix, the FDA-accepted tools; Schoemaker RJ et al., *CPT Pharmacometrics Syst Pharmacol* 8:583–592, 2019, doi:10.1002/psp4.12471, PMID: 31294544) incorporating typical patient variability in CYP3A4 activity (±40%), body weight (50–100 kg range), and renal function (CrCl 30–120 mL/min). The output is a full predicted plasma concentration distribution across 1000 virtual patients — not a single predicted value but a probabilistic range.

**Gold standard for evaluation:**  
For any compound in the library that has published human PK data (approved drug, clinical candidate with published Phase I results), BioMate's predictions are compared against observed values. Published benchmarks: predicted Cmax within 2-fold of observed in 65% of cases with standard QSPR models; BioMate target is to match or exceed this benchmark using integrated ADME data from the partner.

**Wet lab feedback checkpoint (Month 7):**  
Partner runs mouse or rat PK (single-dose IV + PO) for the top 2 compounds. BioMate uses the in vivo rodent PK data to calibrate the human scaling prediction (allometric scaling with brain/gut correction for CNS or GI-penetrant compounds). The calibrated model updates the human dose prediction.

---

### Stage E — Human Response Prediction and Safety Margin Assessment (Months 7–9)

Stage D predicts what the drug does to the body (PK). Stage E predicts what the body does in response to the drug — the pharmacodynamic (PD) endpoint.

**What BioMate does in this stage:**

*Exposure–response modelling:*

BioMate builds a PK/PD model linking the predicted plasma concentration (from Stage D) to the predicted biological effect. The specific model depends on the target:

| Target class | PD endpoint | Model |
|---|---|---|
| Enzyme inhibitor | % enzyme inhibition | Emax: E = Emax × C / (IC50 + C) |
| GPCR agonist/antagonist | cAMP, β-arrestin, downstream signalling | Operational model of pharmacological agonism (Black-Leff, 1983) |
| Ion channel blocker | Action potential duration (cardiac safety) | O'Hara-Rudy ventricular cell model (FDA-accepted for hERG risk) |
| Kinase inhibitor | % phosphorylation inhibition; tumour growth inhibition (mouse-to-human scaled) | Simeoni TGI model (Simeoni M et al., *Cancer Res* 64:1094, 2004, doi:10.1158/0008-5472.CAN-03-2524) |

*Clinical safety margin:*

For each compound, BioMate computes:
- **Therapeutic index (TI):** TD50 (toxic dose in 50% of patients, estimated from ADMET plus the PK model) / ED50 (effective dose predicted by the PK/PD model)
- **Safety margin against hERG:** predicted free plasma Cmax at the therapeutic dose vs. in vitro hERG IC50 (regulatory standard: ≥ 30× safety margin required; ≥ 100× preferred)
- **Hepatotoxicity risk at Cmax:** DILI score at predicted hepatic peak concentration (not just in vitro incubation concentration)
- **Projected adverse event probability at first-in-human dose:** Monte Carlo simulation across the 1000 virtual patients from Stage D; reports probability that a patient exceeds the safety threshold for each toxicity flag

*Wet lab validation of response prediction:*

The partner's team tests the top 2 compounds in a cellular or biochemical efficacy assay at the concentrations BioMate predicted to be efficacious and safe. The comparison is specific and quantitative: BioMate predicts "at 500 nM free drug, enzyme inhibition should be 75% ± 12% (95% CI)." The partner measures inhibition at 500 nM in the relevant cell line. Agreement within the predicted CI is a successful validation.

---

## The Wet Lab Feedback Loop — Architecture

The most distinctive feature of this extended protocol is the closed DMTA loop. Every stage above includes a "wet lab feedback checkpoint" — but here is the integrated architecture:

```
BioMate (Computational)                    Partner Lab (Wet Lab)
─────────────────────────────────          ──────────────────────────────
Stage A: Structure + Docking
  → Top 5 compounds ranked               → Synthesise / order top 3–5
  ← SPR / ITC binding data              ←
  → Rescored docking model updated
  
Stage B: MD + FEP
  → Binding stability + ΔΔG ranking     → SPR kinetics (kon, koff)
  ← Experimental ΔG values             ←
  → FEP protocol calibrated
  
Stage C: REINVENT4 generation
  → 20 novel designs per round          → Synthesise 5 per round (3 rounds)
  ← IC50 (primary assay)               ←
  → Reward function updated with IC50
  → AiZynthFinder routes for next round
  
Stage D: PK prediction
  → Dose prediction + PK profile        → Mouse/rat PK (IV + PO, n=3)
  ← in vivo PK data (AUC, Cmax, t½)   ←
  → Human scaling calibrated
  
Stage E: PD + safety margin
  → Cellular efficacy prediction        → Efficacy assay at 3 concentrations
  ← % inhibition at each conc.         ←
  → Final PK/PD model + dose recommendation
```

**Turnaround commitment from BioMate:** All computational outputs returned within 48 hours of receiving wet lab data. The partner's synthesis-to-assay turnaround for 5 compounds is expected to be 2–3 weeks per DMTA round. This gives a complete loop cycle of 3 weeks — versus the industry average of 6–8 weeks for a manual DMTA round.

---

## Study Hypotheses

**H1 — Structure-guided hit enrichment.** Compound ranking from Stage A (experimental-structure-guided docking + pharmacophore filter) shows significantly higher top-3 hit rate in wet lab assay than the partner's baseline docking pipeline. Target: top-3 hit rate ≥ 2× baseline (based on published benchmarks comparing pharmacophore-filtered vs. unfiltered docking: Drwal et al., *J. Cheminformatics* 2013).

**H2 — DMTA loop convergence.** Mean IC50 of the top 3 compounds improves ≥ 3-fold from DMTA Round 1 to Round 3. This is the quantitative measure of whether REINVENT4 + real assay data produces meaningful optimisation or random walk.

**H3 — Translational PK accuracy.** Human PK predictions for the top 2 compounds (Cmax, AUC, t½ at the predicted efficacious dose) fall within 2-fold of the observed values when the compounds enter any in vivo study (rodent or human). Evaluated against either the partner's in vivo rodent data or any published human data for structurally matched compounds.

**H4 — Safety margin prediction.** Predicted hERG safety margin (≥ 30× threshold) and DILI risk correctly classify outcomes in the partner's in vitro hERG patch clamp and hepatocyte cytotoxicity assay for all compounds tested. No compound predicted safe (hERG margin ≥ 30×, DILI score < 0.5) shows in vitro toxicity; no compound predicted unsafe passes in vitro safety.

---

## Division of Labor

| Task | Partner | BioMate |
|---|---|---|
| Target structure (PDB / cryo-EM or AlphaFold) | ✓ | |
| Reference compound with known pose (redocking validation) | ✓ | |
| Initial compound library (10–50 compounds) | ✓ | |
| SPR / ITC binding measurements | ✓ | |
| IC50 from primary assay (Stages C, each round) | ✓ | |
| In vitro ADME: microsomal CLint, Caco-2 Papp, fu,p | ✓ | |
| In vivo rodent PK (Stage D calibration) | ✓ | |
| Cellular efficacy assay (Stage E validation) | ✓ | |
| Stage A: ensemble docking, pharmacophore, binding decomposition | | ✓ |
| Stage B: GROMACS MD (100–200 ns), MM-GBSA, FEP | | ✓ |
| Stage C: REINVENT4 generation, DMTA loop management | | ✓ |
| Stage D: ADME scaling, compartmental PK, PopPK (nlmixr2) | | ✓ |
| Stage E: PK/PD model, safety margin, Monte Carlo | | ✓ |
| AWS compute costs for all BioMate analyses | | ✓ |
| Manuscript preparation (joint) | ✓ | ✓ |

---

## Timeline

| Month | Stage | Milestones | Wet Lab Deliverable |
|---|---|---|---|
| 1 | Setup + Stage A begins | Target structure ingested; docking protocol validated on reference compound; RMSD < 2 Å confirmed | — |
| 2 | Stage A complete + Stage B begins | Top 10 compounds ranked by docking + pharmacophore; first DMTA loop round triggered | SPR/ITC for top 5 compounds due |
| 3 | Stage B complete + Stage C begins | MD stability classified for all 10; FEP ΔΔG for top 3; REINVENT4 Round 1 designs delivered | SPR kinetics for top 5 MD-stable compounds due |
| 4 | Stage C: DMTA Round 1 complete | Round 1 novel designs (top 20); retrosynthesis routes; DMTA loop updated with Round 1 IC50 | Round 1 IC50 for 5 synthesised compounds due |
| 5 | Stage C: DMTA Round 2 complete | Round 2 designs based on updated reward function; Round 2 IC50 integrated | Round 2 IC50 due |
| 6 | Stage C: DMTA Round 3 + Stage D begins | Final 20 REINVENT4 compounds; Round 3 IC50 confirms ≥ 3× IC50 improvement; PK scaling for top 3 compounds | Round 3 IC50 due |
| 7 | Stage D complete | Human PK profiles for top 3 compounds; dose prediction at therapeutic window | Rodent PK (IV + PO) for top 2 compounds due |
| 8 | Stage E begins + data compilation | PK/PD model for all target classes; safety margins computed; cellular efficacy predictions generated | Cellular efficacy assay (3 concentrations × 2 compounds) due |
| 9 | Stage E complete + manuscript | Full human response prediction; safety margin report; manuscript draft | Final in vitro safety assay (hERG, hepatocyte cytotox) due |

---

## Deliverables

1. **Complete computational package for the top 3 lead compounds:** Docking poses, MD trajectories (100 ns), FEP ΔΔG values, REINVENT4 design lineage, ADME predictions, full PK/PD profiles, safety margins, and human dose recommendation. Formatted for inclusion in an IND-enabling package.

2. **DMTA loop benchmark:** A time-stamped record of each design-synthesise-test cycle, showing the IC50 trajectory over 3 rounds and the specific structural features that drove improvement — the first such benchmark for an AI-assisted DMTA loop in an academic drug discovery setting.

3. **Translational accuracy report:** For each compound, a table comparing BioMate's predictions versus wet lab measurements at each stage: binding KD, IC50, CLint, Cmax/AUC in rodent (if available), safety flags. The primary scientific contribution of the study.

4. **Peer-reviewed manuscript:** Target journals — *Journal of Medicinal Chemistry* or *ACS Medicinal Chemistry Letters* (for a drug-discovery-first audience) or *Nature Methods* (if the platform methodology is the primary story). Co-authorship with the partner lab; BioMate as corresponding author on the platform description.

---

## Why This Study Matters Beyond the Partner

The central question in AI-assisted drug discovery right now is not "can AI predict binding?" — it can, reasonably well, for known targets. The question is: **does AI-guided design change what compounds a medicinal chemist chooses to make, and are the choices better?**

This study answers that question with a prospective, controlled design:
- The partner lab proceeds with their normal workflow (baseline)
- BioMate runs in parallel, generating an independent ranked list and novel designs
- Both lists are synthesised and tested under the same assay conditions
- The comparison is prospective: neither team knows the assay results until they arrive

The DMTA loop closes with real compounds and real assay data — not a retrospective re-analysis of a public dataset. The human response prediction in Stage E is validated against the actual biology, not against another computational tool.

This is the study design that the AI drug discovery field has been calling for but that almost no published paper has actually executed at this level of prospective rigor.

---

*April 2026 · BioMate AI · Extended study design building on pilot results from Zhejiang People's Hospital and UT Southwestern Simmons Cancer Center*
