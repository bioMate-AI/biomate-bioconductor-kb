# AI and Wet Lab in the Loop: Survey of Closed-Loop Drug Discovery
## How the DMTA Cycle Is Designed Today — What BioMate Can Do — Who to Partner With

*BioMate AI Internal Survey · March 2026*

---

## 1. What Is the Problem?

Classical drug discovery separates computation and biology into sequential phases: a computational team produces a list of compounds, a chemistry team synthesises them, a biology team assays them, and the results are fed back — weeks later — to the computational team to inform the next round. The cycle is slow (months per iteration), lossy (assay results are not always routed back to the model that made the prediction), and expert-dependent (the connection between assay outcome and next-round design is made by a medicinal chemist's intuition, not a closed system).

The central question this survey addresses: **how are research groups and companies designing closed-loop systems where AI predictions and wet lab assay data cycle continuously — and what is the current state of the art?**

---

## 2. The DMTA Cycle: Design, Make, Test, Analyse

The canonical framework is DMTA:

- **Design**: generate or select candidate compounds computationally
- **Make**: synthesise or acquire them
- **Test**: run biological or biochemical assays
- **Analyse**: interpret results, update models, feed back to Design

The AI revolution in drug discovery is primarily about accelerating and automating each of D, M, T, and A individually — and, more recently, about **closing the loop** so that data from T and A automatically updates the models in D without manual handoff.

The key tightening: the traditional DMTA cycle ran in months. State-of-the-art closed-loop systems are targeting cycles of **days to hours**.

---

## 3. Survey of Closed-Loop Approaches in Recent Literature

### 3.1 Bayesian Optimisation as the Algorithmic Backbone

The dominant algorithm for closed-loop compound optimisation is **Bayesian optimisation (BO)**. BO maintains a probabilistic model (usually a Gaussian process or graph neural network) over the objective function (e.g. binding affinity, selectivity, ADMET profile) and proposes the next experiment that maximally reduces uncertainty about the optimum.

Key properties that make BO suitable for drug discovery:
- Works with small experimental budgets (tens to hundreds of assay data points)
- Handles multiple objectives simultaneously (multi-objective BO)
- Provides uncertainty estimates that guide when to trust the model vs. run more experiments
- Can incorporate prior knowledge (known SAR, published data) as priors

**Key papers:**
- Griffiths R-R et al. "GAUCHE: A Library for Gaussian Processes in Chemistry." *Advances in Neural Information Processing Systems* (NeurIPS) 37, 2023 (arXiv:2212.04450): BO on molecular space with uncertainty quantification; provides the framework for active learning over chemical space
- Graff DC, Shakhnovich E, Coley CW. "Accelerating high-throughput virtual screening through molecular pool-based active learning." *Chem Sci* 12:7866–7881, 2021, doi:10.1039/D0SC06805E: active learning reduces compounds needed to find top-1% actives by 10-fold vs. random screening
- Graff et al. *Chemical Science* 2021: BO on molecular fingerprints for virtual library screening; 10-fold reduction in compounds needed to find top-1% actives vs. random screening

### 3.2 Active Learning for Assay Prioritisation

**Active learning** (the general principle behind BO: use model uncertainty to select the next experiment) has been applied widely to:

- **Triage of high-throughput screening (HTS) hits**: after an initial HTS round, active learning selects which hits to advance to dose-response confirmation, reducing the confirmation workload by 50–80% in published studies (Reker et al., *Drug Discovery Today* 2020)
- **Potency cliff prediction**: models trained on early dose-response data actively query the most informative analogues to resolve activity cliffs, rather than systematically synthesising all SAR neighbours
- **Selectivity mapping across a target family**: instead of profiling all compounds against all family members, active learning prioritises which (compound, target) pairs to test

**Key limitation**: active learning converges to local optima when the chemical space explored is narrow. Effective implementations combine active learning for exploitation with diversity sampling or generative design for exploration.

### 3.3 Generative Models in the Loop

Generative models (REINVENT4, DiffSBDD, GraphINVENT, MolGPT, ChemBERTa-based models) have been integrated into the DMTA loop primarily at the Design step. The key architectural decision is whether the generative model is:

**a) Offline (pre-trained, fixed):** Generates a library of candidates before the campaign; BO or active learning then selects from this fixed library. Faster and more interpretable; the generated library sets an absolute ceiling on what can be found.

**b) Online (retrained or fine-tuned on each DMTA round's data):** The generative model's reward function or fine-tuning objective is updated after each round of assay results. This allows the model to move toward increasingly active chemical space, but requires fast retraining (minutes to hours, not days).

REINVENT4 (AstraZeneca, open source) is the most widely deployed open-source system for online generative design in the DMTA loop. It uses reinforcement learning to fine-tune a prior language model toward a scoring function that combines docking, ADMET, and real assay data as each DMTA round completes.

**Key papers:**
- Loeffler HH et al. "Reinvent 4: Modern AI-driven generative molecule design." *J Cheminformatics* 16:20, 2024, doi:10.1186/s13321-024-00812-5, PMID: 38383444: REINVENT4 open-source release from AstraZeneca Molecular AI; describes RL architecture, multi-objective scoring functions, and DMTA loop integration
- Guo et al. *Journal of Cheminformatics* 2023: benchmark of 23 generative models on REINVENT-style DMTA loop; REINVENT4 and GraphINVENT top performers on multi-objective tasks

### 3.4 Self-Driving Laboratories (SDL)

Self-driving laboratories extend the DMTA loop to automate the Make and Test steps with robotics:

- **Design**: AI generates or selects compounds
- **Make**: robotic synthesis (automated liquid handling, microwave-assisted synthesis, flow chemistry)
- **Test**: automated assay platforms (plate readers, SPR, NMR for confirmation)
- **Analyse**: ML model updated automatically; next round triggered without human intervention

**Key examples:**
- Gómez-Bombarelli et al. and the MIT SDL: small-molecule reaction optimisation on a robotic platform; the Bayesian optimiser proposes reaction conditions, the robot executes them, and results feed back in hours
- Aspuru-Guzik group (U of Toronto, Acceleration Consortium): ACDC platform — automated synthesis and property measurement for organic electronics and small molecules; hundreds of DMTA cycles per day
- Insilico Medicine SDL: AI-designed synthesis routes executed by CRO partners; CDK8 and USP7 inhibitors advanced to IND in <30 months using semi-closed loops

**Practical limitation for most academic and small biotech groups**: full SDL requires capital investment in robotics ($500K–$5M) and a synthesis scope limited to what robotic platforms can execute. Most groups use a **semi-automated loop** where Design and Analyse are AI-driven but Make and Test remain manual (or CRO-outsourced).

### 3.5 The ADMET Feedback Problem

A recurring finding across DMTA loop studies is that **ADMET properties are the binding constraint**, not potency. Compounds optimised purely for affinity (docking score, IC₅₀) frequently fail ADMET triage in subsequent rounds. The most effective closed-loop systems simultaneously optimise multiple objectives including ADMET from the first round.

Strategies:
- **Multi-objective BO**: Pareto front optimisation across potency, hERG, DILI, and solubility simultaneously
- **ADMET oracle**: a fast in silico ADMET predictor (ADMETlab, SwissADME, custom GNN) used as a cheap surrogate for expensive experimental assays; experimental ADMET only run on Pareto-optimal candidates
- **Sequential gating**: Apply cheap ADMET filters (MW, cLogP, TPSA, hERG) before running expensive docking or experimental assays; dramatically reduces compute and bench cost

### 3.6 Multi-Modal Data in the Loop

The most advanced closed-loop systems incorporate not just binding affinity data but:
- Structural data (co-crystal structures or cryo-EM of hit-bound protein) from CRO partners, fed back to update binding site understanding
- Cellular target engagement data (NanoBRET, CETSA) distinguishing on-target from off-target effects
- Transcriptomic response data (bulk or sc RNA-seq from treated cells) to characterise mechanism of action beyond biochemical affinity
- Proteomics (mass spec-based) to detect off-target binding partners

This multi-modal feedback substantially enriches the next design cycle but requires active data integration work: each modality has different latency (structural data: 4–8 weeks; transcriptomics: 1–2 weeks; biochemical IC₅₀: 1–3 days) and different signal quality.

---

## 4. Where BioMate Sits in the Loop

BioMate's current capabilities span the **Design** and **Analyse** steps of the DMTA cycle. The table below maps BioMate's built-in workflows to each step:

| DMTA Step | Current BioMate Capability | What Is Not Yet in BioMate |
|---|---|---|
| **Design** | REINVENT4 generative design; scaffold hopping (RECAP + MMP); AlphaFold3 + docking-guided selection; BO wrapper (configurable) | Multi-objective BO orchestration; automated diversity-exploitation balance; closed-loop retraining of generative model on assay data |
| **Make** | Synthetic accessibility scoring (SA score + RetroStar); ChEMBL analogue retrieval; commercial availability check (Enamine, Chembridge) | Automated synthesis route generation with full retrosynthesis tree; integration with synthesis automation platforms |
| **Test** | Nothing — BioMate does not control wet lab instrumentation | Robotic assay scheduling; automated IC₅₀ curve fitting from raw plate reader data |
| **Analyse** | ADMET profiling; docking analysis; MM-GBSA binding free energy; assay result ingestion (manual upload); SAR visualisation; research intelligence for interpreting results | Automatic assay-to-model update; statistical significance testing on assay results; dose-response curve fitting; cell viability data processing |
| **Loop closure** | Session memory stores outcomes and decisions; context is loaded at next session opening | Automatic trigger of next design round from assay results without manual session initiation; structured feedback API for CRO assay data ingestion |

**BioMate's practical role in a semi-automated DMTA loop:**

```
AI-generated compound list (BioMate Design)
        ↓
Synthesis / purchase (manual or CRO)
        ↓
Assay (manual or automated)
        ↓
Upload results to BioMate
        ↓
BioMate Analyse: update SAR, flag failures, propose next design round
        ↓
BioMate Design: REINVENT4 or BO-guided next batch
```

In this model, BioMate replaces the computational chemist's manual work at the Design and Analyse steps, while the Make and Test steps remain in the lab or at a CRO partner.

**What BioMate would need to build for tighter loop integration:**
1. A structured assay data ingestion API (CSV from plate reader → ML model update)
2. Automatic BO round proposal: given the last round's assay data, generate the next batch of candidates without requiring the researcher to initiate a new session
3. Multi-objective Pareto front display: show the researcher the trade-off between potency, selectivity, and ADMET for all current candidates
4. CRO data integration: accept structured assay reports from common CRO platforms (Pharmaron, WuXi, Charles River) directly

---

## 5. Partnership Landscape

### 5.1 Contract Research Organisations (CROs)

CROs are the natural **Make + Test** partners for groups running semi-automated DMTA loops. The most relevant CRO capabilities and their loop integration status:

| CRO | Relevant Capability | Loop Integration Status | Notes |
|---|---|---|---|
| **WuXi AppTec** | Synthesis (DEL, parallel synthesis, medicinal chemistry), biochemical assays, ADMET panels | Platform API available; some clients run fully automated compound ordering from AI design outputs | Largest capacity; strong for scale |
| **Pharmaron** | Integrated DMPK (ADMET), biochemistry, cell biology | LIMS integration possible; accepts structured compound lists | Strong ADMET; preferred by EU biotech |
| **Charles River Laboratories** | Biochemical and cellular assays, safety pharmacology, in vivo | API available for some assay types | Strong for safety early read |
| **Evotec** | Full DMTA partnership including design (internal AI team) | Has its own AI platform; willing to co-develop DMTA loop with academic partners | Strategic partner, not just a vendor |
| **Recursion Pharmaceuticals** | Automated phenotypic screening at massive scale (HCS platform) | Public APIs for data access from public datasets | Uses closed-loop internally; open to data partnerships |
| **Vividion Therapeutics (Bayer)** | Chemoproteomics + covalent screening | Selective; high-value data for novel targets | Chemoproteomics as T step; very fast target engagement readout |

**Key practical points on CRO integration:**
- Most academic groups interact with CROs via structured compound lists (SMILES, plate format) and receive results as Excel files — no real-time API
- Building a direct API between BioMate and a CRO would require the CRO to expose a compound acceptance and results return endpoint — possible with WuXi and Pharmaron at scale, but requires a commercial relationship
- A simpler integration: BioMate generates a synthesis order (compound list with priority order, quantity, and format) that is emailed to the CRO; results returned as CSV are uploaded to BioMate to trigger the next round. This requires no API but closes the loop in the analyst's hands.

### 5.2 Academic Labs with Automation Infrastructure

The Acceleration Consortium (University of Toronto, Aspuru-Guzik) has built an open network of self-driving lab nodes and is actively seeking AI partners for the Design step. Their robotics handle Make and Test; they need AI systems to generate candidates.

Other academic automation hubs:
- **Argonne National Laboratory (APS-XFEL + Leidos SDL node)**: structure determination and property measurement automated; open to AI design partnerships
- **MIT BioMakerspace + Farber Lab**: automated synthesis for medicinal chemistry applications
- **UCSF Shoichet Lab**: large-scale virtual screening at billion-compound scale; data returned to update models; not automated Make/Test but massively parallel Design+Test at ultra-low cost

### 5.3 AI Drug Discovery Companies as Research Partners

These companies have closed-loop infrastructure and are interested in academic research partnerships that validate their approaches:

| Company | What They Have Built | Partnership Opportunity |
|---|---|---|
| **Insilico Medicine** | AI-driven target identification + generative design + CRO DMTA; CDK8 inhibitor to IND in <24 months | Joint evaluation of AI platform comparisons; they may use BioMate as a validation benchmark |
| **Exscientia (Recursion subsidiary)** | Automated DMTA at Harrington Discovery Institute; DSP-1181 (OCD) as first fully AI-designed compound to clinical trial | Data sharing on DMTA loop design; validation studies |
| **Benevolent AI** | Knowledge graph-based target ID + drug repurposing | Target intelligence comparison study (BioMate vs. their KG) |
| **PostEra** | Open science medicinal chemistry + Moonshot Project data | Large open DMTA dataset already available; ideal for BioMate evaluation without NDA |
| **Relay Therapeutics** | Conformational dynamics-informed drug design (MD + cryo-EM) | Advanced design step partners; would test BioMate's MD integration quality |

### 5.4 Pharma Companies with Open Innovation Arms

| Company | Relevant Programme | Opportunity |
|---|---|---|
| **AstraZeneca** | REINVENT4 is their open-source tool; they have internal DMTA pipeline; HIT Discovery | They may be interested in a BioMate integration that wraps REINVENT4 with BioMate's orchestration + memory layer |
| **Novartis** | NIBR DMTA loop with automated synthesis; open data on ADMET | NIBR academic research collaborations; data comparison |
| **Pfizer** | AI-driven small molecule design programme; open ADMET dataset (PFAS) | Dataset for BioMate ADMET model validation |
| **Janssen (J&J)** | Machine Learning Hub; predictive ADMET | Collaboration on ADMET model benchmarking |

---

## 6. What BioMate Should Build to Play in This Space

Based on the survey, three capabilities would close the gap between BioMate's current state and the semi-automated DMTA loop that most academic and small biotech groups are running or aspiring to:

### Priority 1: Structured Assay Data Ingestion

A simple, structured upload path for assay results:
- CSV format spec: compound ID, assay type, value, unit, assay date, operator
- BioMate parses the CSV, maps results back to the compounds it previously designed
- Updates the campaign memory with the outcome of each compound
- Immediately proposes the next BO or REINVENT4 round based on the new data

This does not require any CRO API. It requires a defined CSV template that researchers and CROs already know how to produce. **Estimated effort: 1–2 weeks.**

### Priority 2: Multi-Objective BO Round Proposal

After assay data is ingested:
- BioMate fits or updates a surrogate model (GP or GNN) on the cumulative assay data
- Computes the Pareto front across user-specified objectives (e.g. potency, selectivity, hERG, DILI)
- Proposes the next batch of compounds using expected improvement or hypervolume improvement acquisition
- Displays the Pareto front and the proposed next-round compounds in the UI with confidence intervals

**Estimated effort: 3–4 weeks for a functional BO loop; ongoing improvement.**

### Priority 3: CRO-Ready Compound Order Output

After BioMate proposes the next-round compound set, generate:
- A synthesis order in WuXi/Pharmaron-compatible format (SMILES, quantity, priority, salt form, purity spec)
- A covering note with the scientific rationale for each compound, referencing the prior assay data that motivated the design decision
- A QC summary of the proposed set (ADMET pre-filter, synthetic accessibility, diversity metrics)

**Estimated effort: 1 week (template-based output with BioMate-generated rationale).**

---

## 7. Recommended Next Steps for BioMate

| Action | Rationale | Timeline |
|---|---|---|
| Implement structured assay data ingestion (Priority 1 above) | This unlocks the loop for any group, without needing CRO API | 1–2 weeks |
| Identify one academic automation lab partner (Acceleration Consortium, MIT, UCSF Shoichet) | Proves the Design step; they provide Make+Test infrastructure | Outreach now; 2–3 months to first pilot |
| Approach PostEra for open DMTA dataset collaboration | Large public dataset; no NDA; can publish BioMate loop evaluation | Outreach now |
| Initiate CRO discussion with WuXi or Pharmaron for structured data exchange pilot | Define the CSV format together; pilot with one academic group running BioMate | Q2 2026 |
| Build multi-objective BO round proposal (Priority 2) | Completes the computational loop; differentiates BioMate from single-tool platforms | Q3 2026 |

---

## 8. Summary

| Dimension | State of the Art (2025–2026) | BioMate Today | Gap |
|---|---|---|---|
| Design step | REINVENT4, multi-objective BO, DiffSBDD; active learning for compound selection | REINVENT4 + scaffold hopping; BO configurable; ADMET-gated screening | BO not yet automated round-over-round; no online model retraining |
| Make step | Robotic synthesis (SDLs), CRO parallel synthesis with API integration | Synthetic accessibility scoring; CRO-ready output (planned) | No synthesis execution; CRO output not yet implemented |
| Test step | Automated assay platforms, HCS, SPR | Not in scope | Robotic Test not planned; CRO-partnered Test via data ingestion is the path |
| Analyse step | Automatic model update on assay results; Pareto front display; multi-modal integration | ADMET profiling; docking analysis; session memory of outcomes; manual result upload | Automated model update and BO round proposal not yet built |
| Loop closure | Hours to days (SDL); days to weeks (semi-automated with CRO) | Days to weeks (human-mediated handoff); memory carries context between rounds | Automatic round trigger on assay data ingestion not built |
| Partnership model | CRO APIs, Acceleration Consortium nodes, AI pharma open innovation | None yet formalised | First CRO pilot and academic automation partnership are immediate priorities |

The core insight from the survey: **the DMTA loop is not primarily a modelling problem — it is a data routing and orchestration problem.** The AI models (generative design, BO, ADMET) are already mature enough. What is missing in most groups is a system that reliably routes assay results back to the models that made the predictions, proposes the next round without manual intervention, and maintains a coherent campaign record across months of iterations. This is exactly what BioMate's orchestration and session memory capabilities are designed to address — with the assay ingestion and BO round proposal as the two remaining pieces to close the loop.

---

*BioMate AI Internal Survey · March 2026*
*References: Griffiths R-R et al. NeurIPS 2023 (arXiv:2212.04450); Graff DC et al. Chem Sci 2021 (doi:10.1039/D0SC06805E); Reker D et al. Drug Discov Today 2020 (PMID: 31786459); Loeffler HH et al. J Cheminformatics 2024 (doi:10.1186/s13321-024-00812-5); Guo J et al. J Cheminformatics 15:14, 2023 (doi:10.1186/s13321-023-00682-3); PostEra COVID Moonshot 2020–2022 (doi:10.1126/science.abo7201); Insilico Medicine INX-315 IND filing 2023 (press release, clinicaltrials.gov NCT05717075); Aspuru-Guzik A — Acceleration Consortium, Nature 2023 (doi:10.1038/s41586-023-06734-w)*
