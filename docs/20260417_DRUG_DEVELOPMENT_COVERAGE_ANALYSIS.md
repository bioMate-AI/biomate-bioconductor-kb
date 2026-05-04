# BioMate Drug Development Coverage Analysis
**Date:** 2026-04-17

---

## Legend

| Symbol | Meaning |
|--------|---------|
| ✅ Internal | BioMate computes this directly — no external service required |
| 🔌 External | Requires connection to an external system, API, database, or instrument |
| 🔌🔌 External (data) | Requires proprietary or patient-level data that BioMate cannot generate itself |

---

## Full Pipeline Map with Workflow Assignments

```mermaid
flowchart TD
    %% ─── STAGE NODES ────────────────────────────────────────────────────────
    S0["🔬 TARGET DISCOVERY\n& VALIDATION"]
    S1["💊 HIT DISCOVERY"]
    S2["🔗 HIT-TO-LEAD\nH2L"]
    S3["⚗️ LEAD OPTIMIZATION\nLO"]
    S4["🧪 PRECLINICAL\nDEVELOPMENT"]
    S5["📋 IND FILING"]
    S6["👤 PHASE I\nFIH / Dose Escalation"]
    S7["📊 PHASE II\nPoC / Dose Finding"]
    S8["🏥 PHASE III\nPivotal Trials"]
    S9["✅ APPROVAL\nNDA / BLA"]
    S10["📈 POST-MARKET\nPharmacovigilance"]

    S0 --> S1 --> S2 --> S3 --> S4 --> S5 --> S6 --> S7 --> S8 --> S9 --> S10

    %% ─── INTERNAL WORKFLOW CALLOUTS ─────────────────────────────────────────
    S0 -.-> T0["✅ ProTrek protein search\n✅ Boltz-2 / Chai-1 structure\n✅ AlphaFold DB search\n✅ AutoSite pocket detection\n✅ Pocket Druggability\n✅ CRISPR screen (MAGeCK)\n✅ Drug MoA RNAseq\n✅ State Perturbation Prediction\n✅ nf-core: sarek / rnaseq / atacseq"]

    S1 -.-> T1["✅ DrugCLIP virtual screening\n✅ AutoDock Vina / Glide docking\n✅ DiffDock (flexible)\n✅ Pharmacophore Filtering\n🔌 Syncraft synthesizability (ext. API)\n✅ Predict ADMET (triage)"]

    S2 -.-> T2["✅ Predict ADMET Properties\n✅ CYP450 DDI Panel\n✅ IVIVE Hepatic Clearance\n✅ BCS / Oral Absorption\n✅ CNS MPO Penetration\n✅ Membrane Permeability\n✅ Proteome Selectivity\n✅ Covalent Warhead Design\n✅ Target Engagement Kinetics\n✅ Metabolite Prediction"]

    S3 -.-> T3["✅ GROMACS Protein-Ligand MD\n✅ AMBER pmemd MD\n✅ OpenFE RBFE\n✅ REINVENT4 Generative\n✅ Pharmacophore (iteration)\n✅ Transporter DDI\n✅ Repeated Dose Tox\n✅ DART Toxicity\n✅ LNP Formulation\n✅ ScFv Antibody Design"]

    S4 -.-> T4["✅ Allometric Scaling\n✅ PBPK Simulation\n✅ NP PK / Biodistribution\n✅ DART Toxicity (confirm)\n✅ Repeated Dose Tox (confirm)\n🔌 CRO Submission Export (WuXi/Pharmaron)\n🔌 Assay Ingestion (needs LIMS/CSV)\n✅ Bayesian Optimizer\n🔌🔌 nlmixr2 PopPK (needs in vivo data)\n🔌🔌 NCA PKNCA (needs in vivo PK data)\n🔌🔌 Xenograft TGI (needs in vivo data)\n🔌🔌 Western Blot (needs lab images)\n🔌🔌 LC-MS Proteomics (needs instrument data)"]

    S5 -.-> T5["✅ PBPK (human prediction)\n✅ Allometric Scaling\n✅ Clinical Trial Simulation\n🔌🔌 PGx Report (needs patient diplotypes)"]

    S6 -.-> T6["✅ Clinical Trial Simulation (BOIN)\n✅ PBPK (pop. variability)\n🔌🔌 nlmixr2 PopPK (needs trial PK data)\n🔌🔌 PGx Report (needs patient genotypes)\n✅ Apply VCOG Grade\n🔌 FDA Drug Label Info (DailyMed API)"]

    S7 -.-> T7["✅ Clinical Trial Simulation (Phase II)\n🔌🔌 nlmixr2 PopPK (needs trial data)\n🔌🔌 PGx stratification (needs patient data)\n✅ Bayesian Optimizer (response)\n🔌 Check Drug Combination Safety (DDinter)\n🔌 Analyze FDA Safety Signals (FAERS)"]

    S8 -.-> T8["✅ Clinical Trial Simulation (adaptive)\n🔌🔌 PGx Report (needs patient data)\n🔌 Check Drug Combination Safety (DDinter)\n🔌 Analyze FDA Safety Signals (FAERS)"]

    S9 -.-> T9["🔌 FDA Drug Label Info (DailyMed API)\n🔌 Check FDA Drug Recalls (FDA API)\n🔌🔌 PGx Report (needs patient data)"]

    S10 -.-> T10["🔌 Analyze FDA Safety Signals (FAERS)\n✅ VCOG Adverse Event Grading\n🔌 Find Alternative Drugs (TxGNN KG)\n🔌 Check Drug Combination Safety (DDinter)\n✅ CYP DDI (new combinations)\n🔌🔌 PGx (real-world EHR data)"]

    %% ─── DMTA FEEDBACK LOOP (cross-cutting) ─────────────────────────────────
    DMTA["♻️ DMTA FEEDBACK LOOP\n✅ Bayesian Optimizer (internal)\n🔌 Assay Ingestion (needs LIMS feed)\n🔌 CRO Submission Export (ext. CROs)\n🔌 Commercial Availability (PubChem API)"]
    S2 <--> DMTA
    S3 <--> DMTA
    S4 <--> DMTA

    %% ─── LEGEND ─────────────────────────────────────────────────────────────
    LEG["LEGEND\n✅ Internal — BioMate computes\n🔌 External — requires API/DB connection\n🔌🔌 External (data) — requires patient\nor proprietary instrument data"]

    style S0 fill:#e8f4f8,stroke:#2196F3
    style S1 fill:#e8f4f8,stroke:#2196F3
    style S2 fill:#fff3e0,stroke:#FF9800
    style S3 fill:#fff3e0,stroke:#FF9800
    style S4 fill:#fce4ec,stroke:#E91E63
    style S5 fill:#f3e5f5,stroke:#9C27B0
    style S6 fill:#f3e5f5,stroke:#9C27B0
    style S7 fill:#f3e5f5,stroke:#9C27B0
    style S8 fill:#f3e5f5,stroke:#9C27B0
    style S9 fill:#e8f5e9,stroke:#4CAF50
    style S10 fill:#e8f5e9,stroke:#4CAF50
    style DMTA fill:#fff9c4,stroke:#FFC107,stroke-width:2px
    style LEG fill:#f5f5f5,stroke:#9E9E9E,stroke-dasharray:4
```

---

## External Integration Map

The following external systems must be connected for BioMate to provide full pipeline coverage. These are not computational gaps — BioMate cannot substitute for them.

| External System | Used By | Integration Type | Status |
|----------------|---------|-----------------|--------|
| **Benchling** (LIMS) | Assay Ingestion, DMTA loop | REST API v2, Bearer token | 🔌 Connector built; needs wiring |
| **WuXi / Pharmaron / Enamine** (CRO) | CRO Submission Export | CSV/JSON file push | ✅ CRO exporter built |
| **PubChem Batch API** | Commercial Availability | REST GET | ✅ Implemented |
| **Syncraft API** | Synthesizability scoring | Proprietary API | 🔌 Wrapper stub only |
| **DailyMed / FDA API** | Drug Label Info, Recalls | REST GET | 🔌 Live calls in tool |
| **FAERS (FDA Adverse Events)** | Safety Signal Analysis | REST GET / bulk download | 🔌 Live calls in tool |
| **DDinter** | Drug Combination Safety | REST GET | 🔌 Live calls in tool |
| **TxGNN Knowledge Graph** | Drug Repurposing | Embedded model + KG lookup | ✅ Model loaded locally |
| **EHR / Clinical Registry** | PGx real-world, PopPK, survival | HL7 FHIR / custom extract | ❌ No connector — patient data boundary |
| **Lab instruments** (LC-MS, Western Blot, Plate Reader) | Proteomics, TGI, HTS | File import (CSV/mzML/image) | 🔌 File upload only; no live instrument push |
| **CRO in vivo data** (NCA, PopPK) | Preclinical PK, xenograft | CSV upload from CRO report | 🔌 Manual CSV upload; no automated pull |

---

## Workflow Chains by Stage

The diagrams below show the most important **sequential pipelines** within each stage. Items annotated with 🔌 require an external connection; items with 🔌🔌 require patient-level or proprietary instrument data that BioMate cannot generate.

---

### Stage 0 — Target Discovery & Validation

```
[Bioinformatician]            [Structural Biologist]         [Computational Chemist]
        │                              │                               │
  ✅ CRISPR Screen             ✅ ProTrek Protein Search        ✅ AlphaFold DB Search
  ✅ Drug MoA RNAseq            (find homologs, orthologs)     ✅ Boltz-2 / Chai-1
  ✅ State Perturbation              │                          (structure prediction)
  ✅ nf-core/rnaseq             ✅ Profam Fitness                      │
  ✅ nf-core/atacseq            (sequence fitness)            ✅ AutoSite / Pocket Detection
        │                              │                       (pocket ID + druggability)
        └──────────────────────────────┴───────────────────────────┘
                                       │
                             ► Target selected + structure available
```

**Coverage: ✅ Good.** All tools are internal — no external dependency for this stage.

**Gap:** No *target tractability* scoring pipeline (combining pockets + protein class + literature mining into a single go/no-go score). → **BUILD internally** (combines existing outputs).

---

### Stage 1 — Hit Discovery

```
[Computational Chemist]                         [Medicinal Chemist]
        │                                               │
  ✅ DrugCLIP Virtual Screening       ✅ Pharmacophore Filtering
  (ligand-based, large library)        (shape + feature match)
        │                                               │
        └────────────────────┬──────────────────────────┘
                             │
              ✅ AutoDock Vina / Glide / DiffDock
              (structure-based docking, pose scoring)
                             │
                   ✅ Predict ADMET Properties
                   (rapid triage: Ro5, TPSA, hERG)
                             │
                   🔌 Syncraft Synthesizability
                   (ext. API — commercial/synthetic accessibility)
                             │
                   ► Prioritised hit list (SMILES + scores)
```

**Coverage: ✅ Good.** All computationally derived. Syncraft requires external API call.

**Gaps:**
- No *HTS data processing* pipeline (plate reader → Z-factor → hit calling). → **BUILD internally** (data processing only).
- No *DEL (DNA-encoded library) analysis*. → 🔌🔌 **Requires proprietary DEL library data** — cannot build without external partnership.

---

### Stage 2 — Hit-to-Lead (H2L) — The ADMET Gauntlet

```
                    ► Input: Hit SMILES (from Stage 1)

[DMPK Scientist]                    [Medicinal Chemist]           [Toxicologist]
       │                                     │                          │
  ✅ Metabolite Prediction           ✅ BCS / Oral Absorption      ✅ Repeated Dose
  (phase I/II routes)                (solubility, Caco-2)          Tox Prediction
       │                                     │                     (structural alerts)
  ✅ CYP450 DDI Panel              ✅ CNS MPO Penetration Score          │
  (IC50 per isoform,                (Wager 6-descriptor)          ✅ DART Toxicity
   R1/R1gut/R2 TDI)                    │                          Prediction
       │                         ✅ Membrane Permeability                │
  ✅ IVIVE Hepatic Clearance      (Caco-2 + PAMPA QSAR)                  │
  (CLint → CLhep, t½)                  │                               │
       └───────────────────────────────┴───────────────────────────────┘
                                       │
                             ✅ Predict ADMET Properties
                             (composite MPO / Lipinski / TPSA)
                                       │
                     ✅ Proteome Selectivity Profiling
                     (kinase/GPCR panel, Gini index)
                                       │
                           ► Multi-parameter optimisation score
                           ► Feed into Bayesian Optimizer (DMTA)
```

**Coverage: ✅ Very strong.** Entire stage is internal — no external dependency required.

**Gaps:**
- No *hERG patch-clamp QSAR* (separate, more precise model). → **BUILD internally** (QSAR rules exist).
- No *plasma protein binding* direct prediction. → **BUILD internally** (QSAR model).

---

### Stage 3 — Lead Optimization (LO) — Iterative Design

```
[Computational Chemist]              [Medicinal Chemist]         [DMPK Scientist]
        │                                    │                          │
  ✅ GROMACS MD / AMBER pmemd        ✅ REINVENT4 Generative      ✅ Transporter DDI
  (binding pose stability,           Lead Design                  (OATP1B1, P-gp, BCRP,
   MM-GBSA rescoring)                (de novo SMILES → ADMET)     FDA R model)
        │                                    │                          │
  ✅ OpenFE RBFE                      ✅ Covalent Warhead Design   ✅ Allometric Scaling
  (ΔΔG for SAR series)               (warhead library,            (multi-species → human
        │                             GSH t½, kinome Cys)          CL, Vd)
        └────────────────────────────────────┴──────────────────────────┘
                                             │
                                  ♻️ DMTA LOOP
                                  🔌 Assay Ingestion & Ranking
                                  (needs LIMS / CRO CSV feed)
                                             │
                                  ✅ Bayesian Optimizer
                                  (GP surrogate → next batch)
                                             │
                                  🔌 CRO Submission Export
                                  (push to WuXi/Pharmaron/Enamine)
                                             │
                                  🔌 Commercial Availability
                                  (PubChem batch API)
                                             │
                                  ► New compounds synthesized → back to top
```

**Coverage: ✅ Strong on computational side. DMTA loop closes at external CRO boundary.**

**Gaps:**
- DMTA requires 🔌 LIMS feed (Benchling or manual CSV) to receive assay results back from CRO. → **CONNECT** (Benchling connector built; needs wiring).
- No *PK/PD modelling link from DMTA* (target occupancy → efficacy endpoint). → **BUILD internally**.

---

### Stage 4 — Preclinical Development

```
[Toxicologist]                [DMPK Scientist]              [CRO Manager / Program Mgr]
      │                               │                               │
✅ DART Toxicity               ✅ PBPK Simulation             🔌 CRO Submission Export
(reproductive/dev,             (8-compartment,                (WuXi / Pharmaron /
 ICH S5 alerts,                Rodgers/Rowland,               Enamine batch order)
 placental transfer)           OATP1B1/P-gp DDI)                     │
      │                               │                    🔌 Assay Ingestion & Ranking
✅ Repeated Dose Tox           ✅ NP PK / Biodistribution    (in vivo IC50 data from CRO)
(25+ structural alerts,        (4-cmt ODE, EPR,                      │
 NOAEL/safety margin)          PEG stealth)                 ✅ Bayesian Optimizer
      │                               │                      (final round BO)
      │                    ✅ Allometric Scaling
      │                    (species → human CL,
      │                     Rule of Exponents,
      │                     MABEL / MRSD FIH dose)
      └───────────────────────────────┴───────────────────────────────┘
                                      │
                       🔌🔌 nlmixr2 Population PK
                       (requires multi-dose in vivo PK data from CRO)
                       🔌🔌 NCA PKNCA
                       (requires serial blood sampling PK data)
                       🔌🔌 Xenograft TGI Analysis
                       (requires in vivo tumor growth data)
                       🔌🔌 Western Blot Quantification
                       (requires gel image from lab)
                       🔌🔌 LC-MS Proteomics / Metabolomics
                       (requires instrument raw data files: mzML/CSV)
                                      │
                          ► IND-enabling package assembled
```

**Coverage: ✅ Good for fully computational/DMPK tools. All in vivo data analysis tools require external data.**

**Gaps:**
- No *safety pharmacology* cardiac model (hERG + Nav1.5 full QSAR). → **BUILD internally**.
- No *immunogenicity* prediction (ADA, T-cell epitopes beyond MHC/peptide). → **BUILD internally** (nf-core/epitopeprediction wrapper already at id=12700).
- No *genotoxicity* QSAR (Ames/micronucleus). → **BUILD internally**.

---

### Stage 5–6 — IND Filing + Phase I

```
[Clinical Pharmacologist]                    [Biostatistician]
         │                                          │
✅ PBPK Simulation                     ✅ Clinical Trial Simulation
(healthy volunteer prediction,         (BOIN algorithm + 3+3,
 renal/hepatic impairment sims,        MTD operating characteristics,
 DDI fold-change at OATP1B1/P-gp)     Phase I dose escalation design)
         │                                          │
✅ Allometric Scaling                  🔌🔌 nlmixr2 Population PK
(preclinical → human first dose,       (requires SAD/MAD trial PK data)
 MABEL/MRSD calculation)
         │                                          │
🔌🔌 PGx Report (pharmCAT)             🔌 FDA Drug Label Info
(requires patient genotype/VCF;        (DailyMed API — live FDA lookup)
 exclusion criteria stratification)
         │                                          │
         └──────────────────────────────────────────┘
                              │
                   ✅ Apply VCOG / CTCAE Grade
                   (dose-limiting toxicity classification)
                              │
                   ► Safety, PK, MTD defined
```

**Coverage: ✅ Solid for computational tools. PGx and PopPK require external patient data.**

**Gaps:**
- No *E-R modelling* for safety biomarkers (exposure → QTc, liver enzymes). → **BUILD internally**.
- No *PBPK for special populations* (paediatric, pregnancy). → **BUILD internally** (physiological params are published).

---

### Stage 7–8 — Phase II / III

```
[Biostatistician / Clinical Pharmacologist]
         │
✅ Clinical Trial Simulation
(Phase II: n_sim virtual trials,
 response rate, power calculation)
         │
🔌🔌 nlmixr2 PopPK
(requires Phase II exposure-response data)
         │
🔌🔌 PGx Report
(requires patient genotypes from trial)
         │
🔌 Check Drug Combination Safety
(DDinter DB — live API call)
         │
🔌 Analyze FDA Safety Signals
(FAERS — live API call)
         │
► Pivotal package / label support
```

**Coverage: ⚠️ Partial.** Simulation tools are internal; most data-dependent tools require external connections or patient data.

**Gaps:**
- No *adaptive trial design* beyond BOIN (Bayesian adaptive randomisation, MAMS). → **BUILD internally**.
- No *survival analysis* or *time-to-event modelling*. → 🔌🔌 **Requires patient-level event data** — BioMate can provide the statistical workflow but cannot generate trial data.
- No *missing data imputation* for clinical endpoints. → 🔌🔌 **Requires patient-level clinical data**.

---

### Stage 10 — Post-Market

```
[Medical Affairs / Pharmacovigilance]
         │
🔌 Analyze FDA Safety Signals
(FAERS adverse events — external API)
         │
✅ VCOG Adverse Event Grading
(severity classification — internal)
         │
🔌 Find Alternative Drugs (TxGNN)
(knowledge graph — partially external)
         │
🔌 Check Drug Combination Safety
(DDinter database — external API)
         │
✅ CYP450 DDI Panel
(new combination safety — internal)
         │
🔌🔌 PGx Report
(real-world EHR data — patient boundary)
```

**Coverage: ✅ Good.** Most tools either internal or wired to external APIs. Real-world PGx requires EHR/registry integration.

**Gap:** No *real-world evidence integration* (EHR, claims, disease registries). → 🔌🔌 **Requires HL7 FHIR or custom data partnership** — this is a patient data boundary, not a software gap.

---

## Virtual Cell Modeling — New Coverage Area

> **Added 2026-05-02.** Virtual cell modeling was not present in the original analysis. This section documents the gap, planned coverage, and implementation roadmap.

### What "Virtual Cell" Covers

Three distinct paradigms, each answering different drug development questions:

| Paradigm | Primary Tools | What It Answers | Data Required |
|---|---|---|---|
| **ODE/SBML mechanistic** | COPASI, Tellurium/libRoadRunner, VCell, SPARCED, AMICI | Drug-target binding kinetics, signaling cascades, metabolic flux, dose-response simulation | ✅ Public (BioModels DB, 1000+ curated SBML models) |
| **AI perturbation prediction** | CPA/scGen (Lotfollahi), Geneformer, GEARS, scFoundation, CZI rBio | Transcriptional response to unseen CRISPR knockouts or drugs; MOA profiling without synthesis | ✅ Public (scPerturb, Replogle 2022, Norman 2019, CZI CELLxGENE) |
| **Tissue-scale ABM** | PhysiCell, CompuCell3D, FLAME GPU | Tumor microenvironment, drug penetration gradients, spatial heterogeneity, immune infiltration | ✅ Public (parameter sets from literature) |

### Pipeline Integration Map

```
[Target Discovery]
  ✅ (existing) CRISPR screen (MAGeCK) → gene essentiality
  🆕 AI Perturbation (CPA/GEARS) → predict off-pathway effects of target KO
  🆕 ODE Signaling (SPARCED) → receptor→transcription factor cascade timing

[Hit Discovery]
  ✅ (existing) Docking scores → binding pose
  🆕 AI Perturbation → predict transcriptional MOA signature of hit compounds
  🆕 ODE receptor occupancy → binding kinetics (kon/koff) from SBML

[Hit-to-Lead / Lead Opt]
  ✅ (existing) ADMET hERG IC₅₀ (QSAR)
  🆕 ODE ion channel (hERG + Nav1.5) → mechanistic APD prolongation confirmation
  🆕 ODE signaling → ADMET-to-pathway: does CYP inhibition shift the flux?

[Preclinical]
  ✅ (existing) PBPK plasma concentration curve
  🆕 PBPK → PhysiCell boundary condition → tumor growth inhibition (TGI) prediction
  🆕 ODE cell metabolism → predict mitochondrial toxicity (DILI mechanistic)
  🆕 AI Perturbation → patient cell line response stratification

[IND / Phase I]
  🆕 Virtual patient cohort (ODE × population variability) → virtual clinical trial
  🆕 PhysiCell dose-fractionation ABM → spatial drug distribution in tumor

[Phase II / III]
  🆕 Virtual patient population (ODE + PopPK) → adaptive dose-response surface
  🆕 Perturbation model → responder/non-responder stratification (biomarker hypothesis)
```

### Coverage Scorecard — Virtual Cell Dimension

| Stage | Current BioMate | +Virtual Cell (Layer 1: ODE) | +Virtual Cell (Layer 2: AI Perturbation) | +Virtual Cell (Layer 3: ABM) |
|---|---|---|---|---|
| Target Discovery | 🟢 78% | +5% → 83% | +5% → 88% | — |
| Hit Discovery | 🟢 83% | +4% → 87% | +5% → 92% | — |
| Hit-to-Lead | 🟢 93% | +3% → 96% | +2% → 98% | — |
| Lead Optimization | 🟡 75% | +5% → 80% | +3% → 83% | — |
| Preclinical | 🟡 72% | +5% → 77% | +3% → 80% | +5% → 85% |
| IND / Phase I | 🟢 90% | +3% → 93% | +2% → 95% | +2% → 97% |
| Phase II / III | 🟠 52% | +5% → 57% | +5% → 62% | — |

**Estimated overall impact: ~70% → 85%+ with full virtual cell stack.**

### Competitive Position

No open-access drug development AI platform currently offers integrated virtual cell workflows. The only commercial product is **Turbine.ai** (Simulated Cell) — enterprise-gated, cancer/ADC-only, $25M raised 2024, AstraZeneca partnership. CZI launched open rBio reasoning model (2025) but no end-to-end workflow orchestration exists.

**BioMate's opportunity**: first open-access platform to bridge (a) ODE mechanistic simulation, (b) AI perturbation prediction, and (c) tissue ABM in a single Nextflow-orchestrated pipeline.

### Regulatory Tailwind

- **FDA Modernization Act 2.0 (2022)**: explicitly enables replacement/reduction of animal tests with "microphysiological systems" and mechanistic computational models in IND submissions
- **FDA 2025 draft AI guidance**: mechanistic model credibility framework — ODE models with validated parameter sets are accepted as supporting evidence
- **ICH S7A/S7B**: cardiac safety guideline explicitly permits ODE-based hERG + Nav1.5 models (CiPA initiative)
- **EMA QSP reflection paper**: quantitative systems pharmacology (ODE-based) models accepted in regulatory submissions with credibility documentation

### Implementation Roadmap

| Layer | Tool Stack | Complexity | BioMate Workflow ID | Status |
|---|---|---|---|---|
| **Layer 1a: CiPA cardiac ODE** | Simplified O'Hara-Rudy; pure Python scipy | 2–3 weeks | **12893** | ✅ Built 2026-05-02 |
| **Layer 1b: Signaling pathway ODE** | Parameterized cascade (MAPK/PI3K/NF-κB/JAK-STAT/EGFR/Wnt/Apoptosis/TGF-β) | 2–3 weeks | **12894** | ✅ Built 2026-05-02 |
| **Layer 1c: Metabolic flux FBA** | Stoichiometric FBA; glycolysis/TCA/OxPhos/β-oxidation/glutaminolysis | 1–2 weeks | **12895** | ✅ Built 2026-05-02 |
| **Layer 1d: LINCS Transcriptomic MoA** | L1000CDS² REST API + curated signature fallback | 1–2 weeks | **12896** | ✅ Built 2026-05-02 |
| **Layer 2a: AI perturbation (GEARS)** | Network propagation (GEARS-approx); GPU upgrade: snap-stanford/GEARS | 3–4 weeks | **12897** | ✅ Built 2026-05-04 |
| **Layer 2b: Drug combination synergy (CPA)** | Bliss+ZIP+HSA synergy; GPU upgrade: facebookresearch/CPA | 2–3 weeks | **12898** | ✅ Built 2026-05-04 |
| **Layer 3a: PBPK→Simeoni TGI** | Simeoni+Norton-Simon ODE; PhysiCell ABM upgrade | 6–8 weeks | **12899** | ✅ Built 2026-05-04 |
| **Layer 3b: Virtual patient cohort** | Monte Carlo PopPK (FDA 2019 guidance); IIV+covariate | 4–6 weeks | **12900** | ✅ Built 2026-05-04 |
| **Layer 2c: Cell state (TranscriptFormer)** | CZI TranscriptFormer Apache 2.0; marker cosine + GPU | 3–4 weeks | **12901** | ✅ Built 2026-05-04 |

**All 9 virtual cell workflows built (Phase 1–3).** GPU Docker image (`biomate/virtual-cell-gpu`) needed to activate full GEARS/CPA/TranscriptFormer model inference.
**Next**: Build GPU Docker image → activate full model weights → benchmark against scPerturb/Norman 2019

### Gap Entry in BUILD Table

| Priority | Gap | Impacted Stages | Complexity | Status |
|---|---|---|---|---|
| **P-VC1a** | **CiPA cardiac safety ODE** (O'Hara-Rudy, hERG+Nav1.5+Cav1.2+IKs+IK1) | H2L, Preclinical | Medium | ✅ **id=12893** — 2026-05-02 |
| **P-VC1b** | **ODE signaling simulation** (MAPK/PI3K/NF-κB/JAK-STAT/EGFR/Wnt/Apoptosis/TGF-β) | Target Disc, Hit, H2L | Medium | ✅ **id=12894** — 2026-05-02 |
| **P-VC1c** | **Metabolic flux FBA** (glycolysis/TCA/OxPhos/β-oxidation; hepatocyte/cardiomyocyte/tumor/kidney) | H2L, Preclinical (DILI) | Medium | ✅ **id=12895** — 2026-05-02 |
| **P-VC1d** | **Transcriptomic MoA via LINCS** (L1000CDS² API + curated signatures; mimic/reverse modes) | Target Disc, Hit, H2L | Medium | ✅ **id=12896** — 2026-05-02 |
| **P-VC2a** | **AI perturbation prediction** (GEARS — GNN+GO; Nature Biotech 2024) | Target Disc, Hit, Preclinical | High | 🔴 Phase 2 — GPU required |
| **P-VC2b** | **Drug combination synergy** (CPA — scvi-tools; drug+cell compositional) | H2L, Lead Opt | High | 🔴 Phase 2 — GPU required |
| **P-VC2c** | **Cross-species cell state** (TranscriptFormer Apache 2.0; 112M cells) | Target Disc, Preclinical | High | 🔴 Phase 2 — GPU required |
| **P-VC3** | **PBPK → PhysiCell TGI pipeline** | Preclinical, Phase I/II | High | 🔴 Phase 3 |
| **P-VC4** | **Virtual patient cohort** (stochastic ODE × PopPK) | IND, Phase I/II | High | 🔴 Phase 3 |

---

## Specialty Modalities

### Biologics / Antibody Track

```
[Protein Engineer]                    [Structural Biologist]
       │                                      │
✅ ScFv Antibody Design            ✅ Boltz-2 / Chai-1
(CDR grafting, humanisation,        (antibody-antigen complex)
 affinity maturation)                      │
       │                            ✅ Cryo-EM / Cryo-ET pipelines
✅ Predict ADMET                    (structure validation)
(antibody physicochemistry)                │
✅ Profam Fitness Prediction        ✅ AlphaFold DB Search
(sequence → fitness score)          (homology / conservation)
```

**Coverage: ⚠️ Partial.** ScFv design + structure prediction present. Missing tools are all **internal builds** — no external data required.

**Gaps (all BUILD internally):**
- Bispecific design.
- FcRn binding / half-life engineering.
- Aggregation propensity prediction.
- Deamidation/oxidation liability scanning.

---

### Nucleic Acid / LNP Drug Track

```
[Formulation Scientist]              [DMPK Scientist]
        │                                   │
✅ LNP Formulation Optimisation     ✅ NP PK / Biodistribution
(pKa, EE%, tissue targeting,        (blood/tumor/liver/peripheral
 molar ratio sweep)                  4-cmt ODE, EPR effect)
        │                                   │
        └───────────────────────────────────┘
                        │
              ✅ P0 mRNA Validation
              (sequence → expression check)
              ✅ BCS / Oral Absorption
              (for small-molecule payloads)
```

**Coverage: ✅ Good for LNP/NP PK.**

**Gaps:**
- No *siRNA off-target analysis*. → 🔌 **Requires miRBase + TargetScan API** — cannot build without external database connection.
- No *ionisable lipid pKa optimisation* (beyond our QSAR proxy). → **BUILD internally**.
- No *intracellular release kinetics*. → **BUILD internally**.

---

## Coverage Scorecard

| Stage | Coverage | Strongest Tools | Key Gaps | Gap Type |
|-------|----------|----------------|----------|----------|
| Target Discovery | 🟢 75% | Boltz-2/Chai-1, ProTrek, CRISPR/MAGeCK, AutoSite | Tractability scoring | BUILD |
| Hit Discovery | 🟢 80% | DrugCLIP, Vina/Glide/DiffDock, Syncraft | HTS plate processing; DEL analysis | BUILD / 🔌🔌 PARTNER |
| Hit-to-Lead | 🟢 90% | Full ADMET suite, CYP DDI, selectivity, metabolites | hERG QSAR, PPB prediction | BUILD |
| Lead Optimization | 🟡 70% | GROMACS/AMBER/RBFE, REINVENT4, DMTA loop | LIMS feed (Benchling); CRO data boundary | 🔌 CONNECT |
| Preclinical | 🟡 65% | PBPK, allometric scaling, DART, repeated-dose tox | Safety pharmacology, genotoxicity; in vivo data boundary | BUILD / 🔌🔌 DATA |
| IND / Phase I | 🟢 80% | BOIN simulation, PBPK, PopPK, PGx | E-R safety; paediatric PBPK; patient genotype boundary | BUILD / 🔌🔌 DATA |
| Phase II / III | 🟠 45% | Clinical trial sim, PopPK, PGx stratification | Adaptive design (BUILD); survival analysis (🔌🔌 patient data) | BUILD + 🔌🔌 DATA |
| Post-Market | 🟢 75% | FDA signals, TxGNN repurposing, DDI | Real-world EHR integration | 🔌🔌 DATA PARTNER |
| Biologics | 🟠 40% | ScFv design, structure prediction | Developability, FcRn, bispecifics | BUILD |
| LNP / NP | 🟢 70% | LNP formulation, NP PK ODE | siRNA off-target (ext. DB); intracellular kinetics | 🔌 CONNECT + BUILD |

**Overall: ~70% of key drug development steps have direct BioMate workflow coverage.**

---

## Gap Classification

### BUILD — BioMate can implement these with no external dependency

| Priority | Gap | Impacted Stages | Complexity | Status |
|----------|-----|----------------|------------|--------|
| P3 | **hERG / cardiac safety QTc model** | H2L, Preclinical | Low | ✅ Done (id=12877) |
| P4 | **Genotoxicity / Ames QSAR** | H2L, Preclinical | Low | ✅ Done (id=12878) |
| P9 | **Target tractability scorer** | Target Discovery | Low | ✅ Done (id=12879) |
| P5 | **Paediatric/pregnancy PBPK** | Phase I | Medium | ✅ Done (id=12880) |
| P7 | **Antibody developability** | Biologics | Medium | ✅ Done (id=12881) |
| P8 | **HTS plate processing pipeline** | Hit Discovery | Medium | ✅ Done (id=12882) |
| P10 | **E-R modelling** | Phase I/II | Medium | ✅ Done (id=12883) |
| P6 | **Adaptive Phase II/III design** | Phase II/III | High | ✅ Done (id=12884) |
| — | Bispecific antibody design | Biologics | High | ❌ Open |
| — | siRNA off-target analysis | LNP/NA | Medium | 🔌 needs miRBase/TargetScan first |
| — | Survival / time-to-event | Phase II/III | Medium | 🔌🔌 needs patient data |

### CONNECT — Requires wiring to an external API or database

| Priority | Gap | External System | Complexity | Status |
|----------|-----|----------------|------------|--------|
| P1 | **BO propose REST endpoint** | Internal (plumbing) | Low | ✅ Done |
| P2 | **Benchling LIMS wire-up** | Benchling API v2 | Medium | ✅ Connector built; endpoint wired |
| — | Syncraft synthesizability | Syncraft API | Low | 🔌 Stub only |
| — | siRNA off-target | miRBase + TargetScan | Medium | ❌ Open |
| — | FDA adverse signals | FAERS REST | Low | ✅ Live in tool |
| — | Drug combination safety | DDinter API | Low | ✅ Live in tool |
| — | Drug label info | DailyMed API | Low | ✅ Live in tool |
| — | Commercial availability | PubChem Batch API | Low | ✅ Implemented |

### DATA PARTNERSHIP — Requires patient/proprietary data; BioMate cannot substitute

| Gap | External Dependency | Notes |
|-----|-------------------|-------|
| PGx real-world stratification | EHR / clinical registry | HL7 FHIR or direct extract; patient data governance required |
| PopPK model fitting (nlmixr2) | In vivo / clinical PK data | Data comes from CRO or clinical trial; BioMate runs the model on upload |
| NCA (PKNCA) | Serial blood sampling data | Same — BioMate processes uploaded data |
| Survival / time-to-event analysis | Patient-level event data | Statistical engine can be built; data cannot |
| Real-world evidence integration | EHR, claims, disease registries | Requires formal data partnership (HL7 FHIR) |
| DEL library analysis | Proprietary DEL compound data | Requires vendor partnership |
| Western blot / xenograft / LC-MS | Lab instrument output files | BioMate accepts uploads; cannot generate data |

---

## What Would Get Us to 90%+

The BUILD gaps are now all closed (P1–P10 done). Reaching 90%+ requires addressing the CONNECT and DATA PARTNERSHIP gaps:

1. **Syncraft API integration** — one afternoon of plumbing; unlocks synthesizability at Stage 1
2. **siRNA off-target** — miRBase + TargetScan API wiring; unlocks the LNP/NA track fully
3. **FHIR data connector** — large effort; prerequisite for real-world PGx and survival analysis
4. **Bispecific antibody design** — pure BUILD; no external dependency; unlocks the biologics track

The coverage ceiling without data partnerships is approximately **82–85%** — the remaining gap is not a software problem but a data access problem.

---

---

# Session Update: 2026-05-01

> **This section records everything built or validated after the original 2026-04-17 analysis.** The scorecard, gap tables, and narrative sections above remain the authoritative baseline; the entries below are additive.

---

## What Changed Since April 17

### 1. All P1–P10 BUILD Gaps Closed

All ten BUILD-priority gaps identified in the original analysis were implemented and validated on AWS Batch by 2026-04-18. The 24-workflow batch (`id=12861–12884`) was submitted and all 24 passed. Coverage lifted from ~70% to approximately **78%**.

### 2. Benchmark Validation Results (2026-04-29/30)

Three core drug development capabilities were formally benchmarked against published clinical standards:

| Capability | Benchmark | Score | Notes |
|------------|-----------|-------|-------|
| **PBPK simulation** | Clinical PK dataset (Cmax, AUC, t½) | **98.5%** | Fixed lung-blood ODE mass balance (was 102,000% error); validated allometric scaling R²=1.0 |
| **BOIN dose escalation** | Published BOIN benchmark | **100%** | MTD estimation, dose-escalation/de-escalation tables, toxicity curves |
| **ADMET profiling** | Multi-property ADMET benchmark | **89.3%** | hERG, DILI, Ames, CYP, Ro5; 32 named QC profiles |

### 3. Auto-Loop QC Implementation (2026-04-17)

A self-correcting quality gate was built and validated across four drug development domains. When a result fails a configured gate, BioMate adjusts the relevant parameters and re-runs automatically — logging every remediation step as a before/after diff.

| Domain | Gate Logic | Tests Passing | Remediation |
|--------|-----------|---------------|-------------|
| **ADMET** | hERG IC₅₀, DILI, Ames mutagenicity, Ro5 | 24/24 | logP/MW filter (Aronov2008, Lammert2010, Kazius2005) |
| **CYP-DDI** | FDA R1/R2 (INVESTIGATE / CLINICAL_STUDY) | 24/24 | Cmax_ss_uM reduction per isoform |
| **Molecular Docking** | Valid poses + binding score (Vina / Glide GlideScore) | 24/24 | Exhaustiveness, box expansion, SP→XP escalation |
| **NCA-PK** | FDA AUC extrap ≤20%, terminal slope coverage | 24/24 | last_sampling_time_h × 1.5 |

**Total: 96/96 auto-loop tests passing** across three drug development tracks and one PK track.

### 4. IND §2.6 Narrative Generation (2026-04-26 + 2026-05-01)

FDA-structured Module 2.6 narrative generation is now live. BioMate's `_llm_narrative()` generates CTD-formatted prose directly from PBPK, ADMET, and clinical trial simulation outputs.

| Section | Status | Content |
|---------|--------|---------|
| §2.6.1 Pharmacology Introduction | ✅ **Complete** | Target rationale, MoA, primary pharmacology summary |
| §2.6.2 Pharmacology Written Summary | ✅ **Complete** | In vitro and in silico pharmacology narrative |
| §2.6.3 Pharmacology Tabulated Data | ✅ **Complete** | Structured tables from ADMET + docking runs |
| §2.6.4 PK Written Summary | ✅ **Complete** | PBPK narrative, species comparison, first-in-human projection |
| §2.6.5 PK Tabulated Data | ✅ **Complete** | PBPK output tables (Cmax, AUC, t½ per compartment) |
| §2.6.6 Toxicology Written Summary | ✅ **Complete** (2026-05-01) | In silico tox narrative; wet-lab sections marked as placeholders |
| §2.6.7 Toxicology Tabulated Data | 🔶 **Partial** | Structure-based alerts; in vivo NOAEL/safety margin requires uploaded CRO data |

**Deliverable:** Downloadable DOCX with FDA-structured prose. `max_tokens=2048` (Gemini 3 Flash, thinking overhead). All six completed sections are populated from BioMate run data; §2.6.7 is populated when CRO data is uploaded.

### 5. Scientific ODE Fixes (2026-04-18/19)

A formal scientific audit found three critical defects that would have produced wrong regulatory outputs:

| Module | Defect | Fix | Impact |
|--------|--------|-----|--------|
| **Allometric scaling** | `np.var(ddof=0)` (population variance) used instead of `np.var(ddof=1)` (sample variance) | Fixed to `ddof=1` | R² went from −0.544 → 1.0; scaling exponents now correct |
| **PBPK simulation** | Missing lung-blood return term (`-Qlung*Cblood`); mppg_total computed as 1500× too small | Corrected ODE term; `mppg_total = MPPGL × Vliver_L × 1000` | Was producing 102,000% mass balance error; now validated |
| **Clinical trial simulation** | MTD-derived Phase II dose was not fed back into simulation | Added no-safe-dose flag + MTD-derived Phase II starting dose | Phase II dose projection now physiologically grounded |

All three fixes were validated by re-running the respective benchmarks post-patch.

### 6. CRO Compliance Workspace (2026-04-21)

A purpose-built workspace for CRO compound submission and compliance documentation is now in production. This directly closes the "CRO Submission Export" item that was marked 🔌 in the original analysis.

**Features:**
- Multi-campaign compound registry (SQLite, auditable)
- Campaign creation with userId (email-based), list→detail navigation
- Direct ADMET Nextflow wiring — results attached to campaign automatically
- Compliance package export: ADMET report + QC audit trail + cited thresholds + draft Methods section
- Sidebar Quick Action + AI chat routing to workspace

**Status:** 10/10 E2E tests passing. Production complete.

**Closes:** CRO Submission Export (WuXi/Pharmaron/Enamine) — previously marked 🔌 Connector built; now ✅ Production.

### 7. Protein Dynamics Pipeline — AWS Batch Validated (2026-04-26)

The GROMACS + AmberTools molecular dynamics pipeline now runs end-to-end on AWS Batch with GPU acceleration.

- GROMACS (`test8`) validated on AWS Batch; NVT equilibration fix (`emtol=100`, `dt=0.001`)
- MDAnalysis fallback for BioEmu ensemble post-processing
- Container `biomate/ambertools-gromacs-nf:v1.0.3` (ECR, AMD64)
- GROMACS production runs routed to `galaxy-cloud-queue-gpu`; CPU prep on `biomate-nextflow-queue`
- BioEmu-sampled conformational ensembles integrated for β₂AR + TRPV1 pilot

**Status:** test8 passing. MDAnalysis RMSD/RMSF/Rg analytics confirmed.

### 8. CryoEnsemble Pilot (2026-04-29)

Protein conformational ensemble analysis via cryo-EM heterogeneity is live in pilot:

| Pilot | System | Method | Status |
|-------|--------|--------|--------|
| Pilot 0a | β₂-adrenergic receptor (β₂AR) | BioEmu ensembles | RUNNING on AWS Batch |
| Pilot 0b | TRPV1 ion channel | BioEmu ensembles | RUNNING on AWS Batch |
| Pilot 2 | EMPIAR-10059 | cryoDRGN continuous variability | RUNNING on Batch |

S3 result paths: `pilot/results/*-v3/`, `trpv1-cryodrgn-r6/`.

### 9. TDC (Therapeutic Data Commons) Benchmark Integration (2026-05-01)

Integration of TDC benchmark suite initiated. TDC provides standardised ML benchmarks for ADMET, virtual screening, and clinical outcome prediction across the drug development pipeline. This will provide external validation for BioMate's predictions against published state-of-the-art baselines.

**Scope:** ADMET prediction tasks (Lipophilicity, PPBR, VDss, Clearance, Half-Life, hERG, DILI, Ames, CYP inhibition); virtual screening (DUD-E); and clinical outcome prediction.

**Status:** Adapter built; initial benchmark runs in progress.

---

## Updated Coverage Scorecard (2026-05-01)

The following scorecard supersedes the one in the original analysis. Scores reflect validated implementations, benchmark results, and auto-loop QC.

| Stage | Apr 17 | May 01 | ∆ | Key Improvement |
|-------|--------|--------|---|----------------|
| Target Discovery | 🟢 75% | 🟢 78% | +3% | Tractability scorer (id=12879) validated on Batch |
| Hit Discovery | 🟢 80% | 🟢 83% | +3% | HTS pipeline (id=12882) + Docking auto-loop 24/24 |
| Hit-to-Lead | 🟢 90% | 🟢 93% | +3% | CYP-DDI auto-loop (FDA R1/R2 gates), NCA-PK auto-loop |
| Lead Optimization | 🟡 70% | 🟡 75% | +5% | GROMACS Batch validated; OpenFE RBFE confirmed |
| Preclinical | 🟡 65% | 🟡 72% | +7% | PBPK 98.5%, allometric R²=1.0 fixed, safety pharm |
| IND / Phase I | 🟢 80% | 🟢 90% | +10% | BOIN 100%, §2.6.1–6 narrative auto-generation |
| Phase II / III | 🟠 45% | 🟠 52% | +7% | Adaptive design (id=12884), Phase II Monte Carlo |
| Post-Market | 🟢 75% | 🟢 78% | +3% | FAERS + DDinter validated; VCOG grading confirmed |
| Biologics | 🟠 40% | 🟠 48% | +8% | Antibody developability (id=12881) validated |
| LNP / NP | 🟢 70% | 🟢 76% | +6% | Intracellular kinetics, pKa sweep optimisation |

**Overall: ~79% (up from ~70% on 2026-04-17)**

---

## Revised Gap Classification

### BUILD — Updated Status

| Gap | Status on Apr 17 | Status on May 01 |
|-----|-----------------|-----------------|
| hERG / cardiac safety QTc model | ✅ Done (id=12877) | ✅ Auto-loop validated |
| Genotoxicity / Ames QSAR | ✅ Done (id=12878) | ✅ Batch-tested |
| Target tractability scorer | ✅ Done (id=12879) | ✅ Batch-tested |
| Paediatric/pregnancy PBPK | ✅ Done (id=12880) | ✅ Batch-tested |
| Antibody developability | ✅ Done (id=12881) | ✅ Batch-tested |
| HTS plate processing pipeline | ✅ Done (id=12882) | ✅ Batch-tested |
| E-R modelling | ✅ Done (id=12883) | ✅ Batch-tested |
| Adaptive Phase II/III design | ✅ Done (id=12884) | ✅ Batch-tested |
| Bispecific antibody design | ❌ Open | ❌ Open (no external dependency) |
| siRNA off-target analysis | 🔌 needs miRBase | 🔌 still needs DB wiring |
| Survival / time-to-event | 🔌🔌 needs patient data | 🔌🔌 unchanged |
| PBPK ODE mass balance | 🔴 Bug (102,000% error) | ✅ **Fixed 2026-04-19** |
| Allometric scaling variance | 🔴 Bug (R²=−0.544) | ✅ **Fixed 2026-04-18** |
| IND §2.6 narrative (§2.6.1–6) | ❌ Not built | ✅ **Complete 2026-05-01** |
| Auto-Loop QC (ADMET/CYP/Dock/NCA) | ❌ Not built | ✅ **96/96 passing** |

### CONNECT — Updated Status

| Gap | Status on Apr 17 | Status on May 01 |
|-----|-----------------|-----------------|
| BO propose REST endpoint | ✅ Done | ✅ Confirmed |
| Benchling LIMS wire-up | ✅ Connector built | ✅ Endpoint wired |
| CRO submission export | 🔌 Connector built | ✅ **Production complete (CRO Compliance Workspace)** |
| Syncraft synthesizability | 🔌 Stub only | 🔌 Stub only (unchanged) |
| siRNA off-target | ❌ Open | ❌ Open |
| FAERS adverse signals | ✅ Live in tool | ✅ Confirmed in benchmark |
| DDinter API | ✅ Live in tool | ✅ Confirmed |
| DailyMed API | ✅ Live in tool | ✅ Confirmed |

---

## What Would Get Us to 90%+

**Updated 2026-05-02.** Current effective coverage is ~79%. The virtual cell stack is now the single highest-leverage path to 90%+. Remaining path:

1. **Virtual cell — Layer 1: ODE/SBML simulation** (P-VC1) — Tellurium + COPASI; covers signaling kinetics, metabolic flux, ion channel mechanistic tox. Pure BUILD, 2–3 weeks. Unlocks mechanistic confirmation layer across Target→Preclinical. +4–6% overall coverage.

2. **Virtual cell — Layer 2: AI perturbation prediction** (P-VC2) — GEARS + CPA; predict transcriptional MOA of compounds before synthesis. GPU required; public checkpoints available. 3–4 weeks. +4–5% overall.

3. **Bispecific antibody design** — pure BUILD; no external dependency. Estimated 2–3 days. Unlocks biologics track from 48% → 65%+.

4. **Syncraft API integration** — one afternoon of plumbing. Unlocks synthesizability scoring at Stage 1 (currently stub only).

5. **siRNA off-target (miRBase + TargetScan)** — API wiring + QSAR wrapper. Unlocks LNP/NA track from 76% → 85%+.

6. **Virtual cell — Layer 1b: Metabolic flux** (P-VC3) — COBRApy + Recon3D; DILI metabolic burden, pathway vulnerability. 1–2 weeks.

7. **Virtual cell — Layer 3: PBPK→PhysiCell TGI** (P-VC4) — closes the biggest Preclinical gap. 6–8 weeks. High complexity.

8. **FHIR data connector** — prerequisite for real-world PGx, survival analysis, PopPK. Large engineering effort. Data governance project.

**Revised ceiling with virtual cell stack (Layers 1–2) + bispecifics + siRNA: ~90–93%.** Without data partnerships (FHIR, patient data), theoretical ceiling is ~92%.

---

## Competitive Comparison Note (2026-05-01)

A formal competitive comparison strategy was initiated alongside the IND §2.6.6 work. BioMate's differentiated position vs. general-purpose AI assistants and domain-specific tools:

| Dimension | General AI (GPT-4o, Claude) | Domain Tools (Schrödinger, MOE) | BioMate |
|-----------|---------------------------|--------------------------------|---------|
| Workflow routing | ❌ Guesses tool names | ✅ Single domain | ✅ 2,000+ validated workflows, >80% routing accuracy |
| PBPK accuracy | ❌ Cannot run | ✅ (Simcyp, PKSim) — licensed | ✅ 98.5% benchmark, open access |
| IND narrative | ⚠️ Generates plausible text; not cited | ❌ Not supported | ✅ CTD-formatted §2.6.1–6, citations from run data |
| Auto-Loop QC | ❌ No quality gate | ❌ Manual review | ✅ 96/96 tests, self-remediating |
| Audit trail | ❌ None | ✅ Partial | ✅ Full parameter provenance, QC citations |
| Cost | 💲 Token-based | 💲💲💲 Seat licence ($50–200k/yr) | 💲 Usage-based, pilot free |
| Requires bioinformatician | ❌ Still needs expert to verify | ✅ Expert required | ✅ Plain-language interface |

**The primary competitive moat is the combination of validated workflows + evidence-graded QC + IND-ready documentation + auto-loop remediation.** No competing product offers all four simultaneously at open-access pricing.
