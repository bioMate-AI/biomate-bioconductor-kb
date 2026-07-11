# BioMate Niche Strategy Survey and Proposal
**Date:** 2026-07-08  
**Context:** Strategic session following Zhao Lab RA GWAS / scGWAS pipeline completion

---

## 1. Starting Point: What BioMate Actually Is

BioMate is a **self-evolving workflow execution engine**:
- 2,455 pre-validated bioinformatics workflows (GWAS, RNA-seq, scRNA-seq, ADMET, PBPK, protein structure)
- PostgreSQL-backed agentic memory system: every run writes outcomes, parameters, lessons learned
- Procedural memory tagged by `applicable_domains` — learned procedures transfer across disease contexts
- AWS Batch execution at scale
- Can generate proprietary execution traces usable for fine-tuning specialized LLMs

The platform is always valuable for quick data analysis and can be offered to external users. The strategic question is: **where to go deep to build a moat that is data-driven, model-driven, and hard to replicate.**

---

## 2. Investment Environment Context

From analysis of H1 2026 funding data:
- OpenAI + Anthropic took 43% of all global startup funding
- Seed rounds down 27% YoY; deal count at 5-quarter low
- 5 companies captured 73% of all new committed capital in Q1 2026
- AI has split into: platform capital market (foundation models) vs survival market (everyone else)

**What investors now require:**
- Concrete before/after cost comparisons
- Unit economics that survive 30% inference cost increase
- Proprietary data, distribution, or compliance moat
- Cash flow evidence — not "platform period" storytelling
- Answer to: "What happens when OpenAI ships this natively?"

**BioMate's answer:** We run workflows that foundation models can describe but cannot execute. We accumulate proprietary execution traces that train specialized models no competitor can replicate without running the same volume of real analyses.

---

## 3. Directions Evaluated

### 3.1 Three Original Service Directions (Evaluated and Ranked)

#### Direction 1: Biomarker Stratification for Failed Autoimmune Trials
**Verified evidence:**
- R4RA trial (Nature Medicine 2022): elastic net on synovial RNA-seq predicted rituximab (AUC 0.744) and tocilizumab (AUC 0.681) response in n=133 RA patients
- STRAP trial (Nature Communications July 2025): 8 ML algorithms on n=208 RA patients, AUC 0.748–0.763, externally validated
- SLE serological stratification: RR 1.45, NNT=6.5 across 8 trials (Lupus Sci Med 2026)
- Method confirmed: elastic net > random forest (RF FPR=0.76 vs elastic net FPR=0.11)
- Sample size confirmed: n=130–210 per study is sufficient

**Assessment:**
- Time to revenue: 3–6 months
- Revenue per engagement: $75K–$200K
- Competition: moderate (CROs do this in oncology, less in autoimmune)
- Data moat: low (customer owns the trial data)
- Defensibility: low — competing on price/speed against CROs

**Verdict:** Fastest to revenue but least defensible. Use for early cash flow only.

---

#### Direction 2: Cross-Modality Computational IND Packages
**Verified evidence:**
- PBPK in 26.5% of FDA NDA/BLA approvals 2020–2024 (PMC12655628)
- Autoimmune only 6% of PBPK submissions vs oncology 42% — low incumbent CRO penetration
- ~70–90 new commercial autoimmune INDs per year
- AI-generated IND narratives: 69–78% quality (Weave Bio/Takeda preprint, Sept 2025) — useful draft, not submission-ready
- No AI-generated IND narrative has been submitted to or accepted by FDA
- Certara/Simulations Plus offer PBPK consulting but NOT integrated ADMET+PBPK+narrative packages
- Verified target customer: Coultreon Biopharma ($125M Series A April 2026, SIK3 inhibitor COL-5671, Phase I psoriasis/UC)

**Gap confirmed:** No commercial product integrates ADMET + PBPK + safety pharmacology + written summaries + audit trail in one workflow.

**What's needed to execute:**
- PK-Sim integration (open-source, FDA-familiar)
- Regulatory writing firm as white-label delivery partner
- 21 CFR Part 11 compliant audit trail

**Assessment:**
- Time to revenue: 6–12 months
- Revenue per engagement: $100K–$250K
- Competition: low in autoimmune specifically
- Data moat: medium (audit trail IP, validated parameter sets)
- Defensibility: medium

**Verdict:** Core commercial product once PK-Sim is integrated. Partner with regulatory writing firm rather than hiring in-house.

---

#### Direction 3: Rare Autoimmune Target Discovery (Sjögren's + SSc)
**Verified evidence:**
- Primary Sjögren's 2022 GWAS (Nature Communications): 22 validated risk loci including TYK2 and TNFAIP3
- TYK2 cross-validated: Sjögren's GWAS + Phase 2 in dermatomyositis (GALARISSO, NCT05695950, topline Dec 2025)
- AMP AIM consortium includes Sjögren's — active multi-omic data generation
- SSc 2024 trans-ethnic GWAS: 30 signals across 24 regions (PMC10830486)
- Cabaletta Bio (leading SSc biotech) doing CAR-T, not small molecules — SSc small molecule space open
- ANCA vasculitis: avacopan (Tavneos) already approved — REMOVE from "no approved therapy" list
- Dermatomyositis: brepocitinib (TYK2/JAK1) PDUFA Q3 2026 — window closing

**Funding confirmed:**
- NCATS RFA-TR-25-002: up to $275K/2 years, deadline June 2, 2027 (NOT-TR-26-009)
- National Scleroderma Foundation: $200K/2–3 years (7 grants awarded in 2024, $1.4M total)
- Scleroderma Research Foundation: $75K/2 years exploratory (March 2026 deadline — missed; next cycle)
- Vasculitis Foundation: $50K/2 years
- No AI company verified as specifically targeting rare autoimmune — space uncontested

**Assessment:**
- Time to revenue: 6–18 months (grant-funded initially)
- Revenue: grant $75K–$275K + biotech contracts
- Competition: near zero
- Data moat: high — disease-specific execution traces
- Defensibility: high

**Verdict:** Best long-term defensible position. Apply to NCATS grant within 6 months. Anchor on TYK2 and IRF5 as cross-disease targets validated in both Sjögren's and SSc.

---

### 3.2 Platform vs Consulting Assessment

| Business type | Revenue model | Margin | Investor multiple | Compounding? |
|---|---|---|---|---|
| Consulting/professional services | Headcount × hours | 20–40% | 1–2× revenue | No |
| Platform with execution traces | Scales without headcount | 70–90% | 10–20× ARR | Yes — each run improves the next |

**Key discipline:** Every professional engagement must generate something that lives in the platform permanently — an execution trace, a validated workflow parameter, a disease-specific knowledge graph entry. If a project ends and nothing is added to the platform, it was consulting.

---

### 3.3 Disease Treatment vs Other Directions

**Patient stratification (ruled out):** Too research-focused, hard to validate commercially, long cycles before payment.

**Synthetic biology:** More connected to physical AI (design-build-test robotic cycles) but requires robotic foundry infrastructure BioMate doesn't have. 12–18 months of workflow development before a sellable product. Skip for now; revisit as 2–3 year expansion.

**Autoimmune vs synthetic biology comparison:**

| | Autoimmune | Synthetic biology |
|---|---|---|
| Market size | $124B drug market today | $20B, growing |
| Physical AI connection | Weak | Strong |
| BioMate readiness | High — build now | Low — 12–18 months away |
| Competition | Moderate | Strong at infrastructure layer |
| Data moat | Medium–high | Low (Ginkgo owns best data) |

---

## 4. Data Moat and Specialized Model Survey

### Framework
The right strategic question is not "who pays" but "what data can BioMate accumulate that trains a model no competitor can train." Scored 1–5 on four dimensions.

---

### Direction A: Autoimmune — Score 16/20

**Data availability: 5/5**
- CellxGene: 50M+ cells, large immune fraction, openly downloadable
- ImmPort: 500+ immunology studies (flow cytometry, gene expression, clinical outcomes)
- AMP AIM: longitudinal multi-omic RA/SLE/Sjögren's/psoriasis data — actively generated
- DICE eQTL: immune cell-specific eQTL across 15 cell types
- UK Biobank: 500K participants, autoimmune phenotypes + genotypes
- dbGaP: disease GWAS with clinical metadata (controlled access, free application)
- GEO: hundreds of autoimmune RNA-seq and scRNA-seq datasets

**Model feasibility: 4/5**

Target model: **Immune Cell Perturbation Predictor**
- Architecture: Geneformer v2 fine-tuned on CellxGene immune atlas + ImmPort perturbation experiments
- Predicts: how target perturbation (gene KO, drug inhibition) shifts Th17/Treg balance
- Current gap: Geneformer trained on 30M mixed cells, not immune-specific. scGPT has immune version but doesn't integrate GWAS signal. No model chains GWAS → cell type → perturbation prediction.
- Training data: NeurIPS 2022 Perturb-seq competition data (public), ImmPort stimulation experiments, CRISPR screen data from GEO

**Moat strength: 4/5**
- Running GWAS→scGWAS→perturbation chain on 500+ autoimmune GEO datasets creates proprietary execution traces
- Parameter knowledge (e.g., Entrez→symbol conversion requirement for scGWAS, Box-Cox λ ranges for different GWAS distributions) accumulates in procedural memory
- Competitors would need to run the same volume to replicate

**Customer clarity: 3/5**
- Pharma translational teams, rare disease biotechs, academic immunology labs
- Not immediate revenue; grant-fundable and credibility-building

**Confirmed model gap (verified 3-0, two independent 2025 papers):**
- scGPT and scFoundation are **outperformed by a mean-of-training-examples baseline** on perturbation prediction across four standard Perturb-seq datasets (Adamson, Norman, Replogle K562, Replogle RPE1)
- 9 ICI responder prediction models all fail cross-cohort generalization — clinical translation unsolved
- CFM-GP shows +22.3% improvement on IFN-beta stimulated lupus PBMCs (GSE96583) but novel perturbation performance unvalidated
- AMP AIM is building a 5-disease cross-autoimmune atlas — no perturbation foundation model trained on it exists

**Target model: Cross-Disease Immune Perturbation Predictor**
- Train on immune-specific scRNA + perturbation labels
- Evaluate on cross-cohort held-out sets (where all current models fail)
- Publish cross-cohort generalization results — this is the credibility anchor

**Top 3 datasets to start (with accessions):**
1. **GSE96583** — IFN-beta stimulated lupus PBMCs, Perturb-seq, publicly available on GEO
2. **Replogle K562 + RPE1** — large-scale Perturb-seq benchmarks, publicly available
3. **AMP AIM data releases** — as available; NCATS grant positions BioMate to access early

**6-month actions:**
1. Download GSE96583 + Replogle datasets → run through BioMate scRNA pipeline → generate immune perturbation execution traces
2. Fine-tune Geneformer v2 on immune-specific data with perturbation labels; evaluate on cross-cohort held-out sets
3. Apply to NCATS RFA-TR-25-002 with Sjögren's cross-disease perturbation prediction as deliverable
4. Submit benchmark paper on cross-cohort generalization — positions BioMate against the 9-model failure landscape

---

### Direction B: Microbiome Therapeutics — Score 14/20

**Data availability: 4/5**
- curatedMetagenomicData: 20,000+ samples with clinical metadata and disease labels — standardized
- HMP (Human Microbiome Project): 16S + metagenomics across body sites
- MicrobiomeDB: integrated disease-microbiome associations
- GMrepo: gut microbiome + phenotype database
- iHMP (IBD-specific): longitudinal microbiome + host multi-omic data
- GEO disease-specific: colorectal cancer, T2D, RA microbiome studies

**Model feasibility: 3/5**

Target model: **Disease-Specific Microbiome Intervention Predictor**
- Predicts: given baseline microbiome composition, which probiotic/prebiotic/FMT intervention shifts composition toward healthy state
- Current gap: MetaPhlAn/HUMAnN do taxonomy + pathway annotation, zero intervention prediction. No foundation model trained on paired baseline→post-intervention data.
- Challenge: intervention response data is sparse; paired samples across curatedMetagenomicData vary in quality

**Moat strength: 4/5**
- curatedMetagenomicData is systematically underprocessed — no one has run a unified computational pipeline across all 20K samples
- Seres and Vedanta failed Phase 2 partly due to absence of computational patient stratification — that problem is unsolved
- Paired pre/post intervention data, once processed, is proprietary in combination

**Customer clarity: 3/5**
- Microbiome biotech startups (Vedanta, Finch Therapeutics, BiomeBank)
- Functional food / precision nutrition companies (Danone, Nestlé Health Science)
- Precision nutrition startups — shorter validation cycle than pharma

**Top 3 datasets to start:**
1. curatedMetagenomicData R package — 20K samples, standardized, direct download
2. iHMP (Integrative Human Microbiome Project) — IBD longitudinal, dbGaP phs001719
3. GMrepo v2 — disease-associated gut microbiome, web download

**6-month actions:**
1. Run all curatedMetagenomicData samples through BioMate metagenomics pipeline — generate disease-stratified microbiome profiles
2. Train intervention classifier on paired pre/post samples (IBD, T2D datasets)
3. Approach precision nutrition companies with validated classifier as pilot product

---

### Direction C: Longevity / Aging — Score 13/20

**Data availability: 3/5**
- GTEx: gene expression across tissues and ages — good but not longitudinal
- UK Biobank: methylation data for clock training (some available)
- CellxGene aging atlas: emerging, not yet comprehensive
- Clock training data: Horvath original partially public; GrimAge training data proprietary

**Model feasibility: 4/5**

Target model: **Multi-omic Biological Age Predictor + Intervention Safety Screener**
- Predicts biological age from multi-omic input; screens longevity interventions (rapamycin, senolytics, epigenetic reprogramming) for safety in given cell context
- Current gap: existing clocks (Horvath, DunedinPACE, GrimAge) are single-modality (methylation only), don't predict intervention response

**Moat strength: 3/5**
- Window is closing — Altos Labs ($3B), Calico, NewLimit building in-house
- 12-month window before they publish and establish the standard models

**Customer clarity: 3/5**
- Longevity supplement companies, clinical longevity practices, small aging biotechs
- Large longevity labs are competitors, not customers

**Verdict:** Investigate further but timing is the risk. Second-mover disadvantage growing.

---

### Direction D: Microbiome Therapeutics — REMOVED

**Verdict: Skip.** Adversarially verified research confirmed that Seres/Vedanta Phase 2 failures were biological and clinical in nature, not computational. Zero confirmed external demand for computational workflow platforms in LBP development. Earlier 14/20 score was based on unverified reasoning.

---

### Direction E: Longevity / Aging — REMOVED

**Verdict: Skip.** Altos Labs, Calico, and NewLimit build computational platforms in-house. Zero confirmed external procurement signals. Revisit only after direct customer discovery calls with computational biology leads at longevity labs.

---

### Direction F: Biosecurity / Pandemic Preparedness — VERIFIED NEW SIGNAL

**Customer clarity: 4/5** — real government procurement confirmed:
- CDC paid UCSC $2.52M over 2 years for pathogen-tracing bioinformatics workflow platform (UShER and related tools) — direct match for BioMate's genomics/variant-calling stack
- DARPA AI BTO Pitch Day (Dec 2024): 42 same-day awards, $6.3M total, tiers of $100K/$200K/$300K per project
- Sales cycle: 3–6 months minimum for DoD; can extend to 12+ months for complex programs

**Data availability: 4/5** — pathogen genomics databases (NCBI, GISAID, GenBank), surveillance sequencing data from CDC and WHO, publicly available outbreak datasets

**Model feasibility: 3/5** — pathogen variant calling, outbreak tracing, vaccine target prioritization. BioMate's existing GWAS and variant-calling workflows apply directly with domain adaptation.

**Moat strength: 3/5** — government relationships and security clearances become a moat over time; initial entry via DARPA Pitch Day is accessible

**Verdict: Pursue as near-term government revenue stream.** Not the deep delivery focus, but a validated revenue path that uses BioMate's existing workflow substrate. Entry point: DARPA Pitch Day application.

---

### Direction G: Synthetic Biology Orchestration — VERIFIED GAP

**Tooling gap confirmed** (3-0 adversarial vote, two 2025 peer-reviewed papers):
- Automation platforms for non-model organisms (Pichia pastoris, Y. lipolytica) lag significantly behind model organisms (E. coli, S. cerevisiae)
- Biofoundries still require skilled staff for orchestration, QC gating, and protocol coordination — Ginkgo's 2025 operations confirmed this
- No general-purpose orchestration platform equivalent to YeastFab exists for non-standard chassis

**BioMate fit:** workflow execution, QC gating, parameter management, and output interpretation are exactly the biofoundry orchestration gap. This is a platform-layer play, not a deep disease focus.

**Verdict: Investigate as platform expansion.** Not the primary deep focus (requires different domain knowledge from autoimmune), but a natural expansion of the "one person does multi-team work" platform value proposition into industrial biotech.

---

### Consolidated Scorecard (Updated)

| Direction | Data | Model | Moat | Customer | Total | Verdict |
|---|---|---|---|---|---|---|
| **Autoimmune (Sjögren's/SSc)** | 5 | 4 | 4 | 3 | **16/20** | Primary deep focus |
| **Biosecurity** | 4 | 3 | 3 | 4 | **14/20** | Near-term revenue |
| **Synbio orchestration** | 3 | 3 | 3 | 3 | **12/20** | Platform expansion |
| **Crop genomics** | 4 | 3 | 3 | 2 | **12/20** | Investigate first |
| **Microbiome** | — | — | — | — | **REMOVED** | Failures were biological |
| **Longevity** | — | — | — | — | **REMOVED** | Build in-house |

---

## 5. Recommended Strategy

### Core Thesis
BioMate builds a **self-improving computational biology platform** that accumulates proprietary execution traces across autoimmune disease and cyclic peptide drug design, trains specialized models on those traces, and becomes progressively harder to replicate as the data flywheel compounds.

The workflow platform serves all users. The specialized models create the moat in specific disease and modality areas.

### Positioning Statement
*"BioMate runs the multi-step computational workflows that foundation models can describe but cannot execute. Every run on real patient data makes our immune perturbation models and disease-specific knowledge base more accurate. We are building what no competitor can replicate without running the same volume of real analyses."*

### Three-Layer Architecture
1. **Platform layer** (existing): workflow execution for any user, any domain
2. **Domain layer** (build now): autoimmune execution traces at scale + cyclic peptide design-ADMET-PK chain; disease-specific parameter knowledge in procedural memory
3. **Model layer** (6–18 months): four specialized models — see Section 5A

---

### 5A. Specialized Model Roadmap (Updated 2026-07-08)

Four models, prioritized by urgency and forcing function:

| Priority | Model | Data | Forcing Function | Timeline |
|---|---|---|---|---|
| **1** | Immune Cell Perturbation Predictor | Arc VCC H1 hESC dataset (300K cells, 300 CRISPRi) + Arc Virtual Cell Atlas (500M cells) + GSE96583 lupus PBMCs | Arc Virtual Cell Challenge 2026 opens Aug 20 — hard deadline, $100K prize, Cell paper | Sprint NOW → Aug 20 start |
| **2** | Macrocycle ADMET Predictor | ChEMBL macrocycles, Pfizer published Caco-2/PAMPA data, PermSMR dataset | VC-directed cyclic peptide focus; no competition but direct product revenue | Months 3–6 |
| **3** | Drug-Immune Perturbation Predictor | LINCS CMap (drug × cell), OP3 benchmark dataset (146 compounds × 4 PBMC populations) | Bridges cyclic peptides → autoimmune: predicts how a macrocycle shifts Th17/Treg balance | Months 6–12 |
| **4** | Cross-Disease Target Ranker | GWAS summary stats + immune perturbation predictions + druggability scores | NCATS grant deliverable; requires Model 1 as input | Months 12–18 |

**Microbiome Intervention Predictor: DROPPED** from model roadmap. Direction removed from strategy due to no confirmed external demand. Resources reallocated to Models 1–3.

#### Model 1: Arc VCC Entry — Immediate Action Required

The Arc Virtual Cell Challenge (arcinstitute.org/virtual-cell-initiative) opens **August 20, 2026**:
- **Task:** predict scRNA-seq profiles of H1 hESCs after CRISPRi single-gene knockdown (few-shot generalization to held-out perturbations)
- **Evaluation:** PDS (Perturbation Discrimination Score), DES (Differential Expression Score), MAE
- **Training data provided:** 300K cells × 300 perturbations + Arc Virtual Cell Atlas (500M cells, public)
- **Prize:** $100K grand prize, $75K generalist prize; Cell journal commentary publication track
- **Key insight from 2025 winner analysis:** mean-of-training-examples baseline was a strong competitor — BioMate's edge must come from autoimmune-specialized pretraining, not a generalist architecture
- **6-week prep (before Aug 20):** Download Arc atlas → fine-tune Geneformer v2 → baseline against mean predictor → iterate on immune-specific cell subsets

This challenge IS the existing Geneformer fine-tuning plan, now with an external validator and a deadline. No new budget required; execution must start immediately.

#### Model 2: Macrocycle ADMET Predictor — New Track

Cyclic peptides (VC-directed, 2026-07-08) require a separate model track. Standard Lipinski/Veber ADMET rules fail for macrocycles; chameleon molecules (different conformer in membrane vs water) are the core prediction challenge.

**Data to curate:**
- ChEMBL macrocycles with Caco-2 permeability: ~3,000–5,000 data points, publicly available
- Pfizer/AstraZeneca published macrocycle ADMET datasets (peer-reviewed papers, 2018–2024)
- PermSMR: ~2,000 macrocycle PAMPA permeability measurements
- Cyclosporin analog series: oral bioavailability paired with conformational data

**Training target:** Predict Caco-2 permeability + P-gp efflux ratio + oral %F for macrocycles from SMILES. Benchmark against standard ADMET tools (ADMETlab, SwissADME) which are calibrated for small molecules and systematically fail on macrocycles.

**BioMate engineering needed:**
- CyclicMPNN integration (Baker lab, 2023): de novo cyclic peptide sequence design from backbone constraint → 2–4 weeks
- RFdiffusion constrained mode: backbone diffusion with cyclic bond constraint → 2 weeks
- Macrocycle ADMET workflow: SMILES → conformer ensemble (RDKit + CREST) → ADMET prediction → flag chameleon behavior

#### Model 4 (Direction 4): Cyclic Peptides in Autoimmune — New Direction

**VC-directed as of 2026-07-08.**

Cyclic peptides occupy the "middle space" between small molecules (oral, cheap) and biologics (potent, selective). For autoimmune specifically:

| Target | Cyclic peptide opportunity | Why now |
|---|---|---|
| IL-17A/F | PPI inhibitor — no approved small molecule; biologics dominate but IV/SC only | RFdiffusion + CyclicMPNN enable de novo design against validated crystal structure |
| Calcineurin (T cell activation) | Voclosporin (cyclosporine analog) approved for lupus nephritis 2021 — proof of concept | Design improved analogs with better selectivity profile |
| IL-6R | Oral macrocycle mimicking tocilizumab binding pocket — open design space | AlphaFold3 handles cyclic peptide docking; no clinical candidate in this class |

**Planned pilot (Month 3–4):** IL-17A as target → BioMate cyclic peptide design sprint:
1. RFdiffusion: generate 100 backbone scaffolds constrained to cyclic bond
2. CyclicMPNN: sequence design on each scaffold
3. AlphaFold3: predict binding to IL-17A crystal structure (PDB: 2VXS)
4. Macrocycle ADMET predictor: screen for oral bioavailability candidates
5. PBPK: estimate human PK for top 3 candidates
6. Propose wet-lab validation to Zhao lab or IL-17 biology collaborator

This produces the first BioMate end-to-end cyclic peptide IND-prep package — direct sellable product to autoimmune biotechs replacing IV biologics with oral candidates.

### Professional Involvement (Right Model)
- **Scientific Advisory Board**: 2–3 KOLs who run real research through BioMate → generate proprietary traces + open doors. Compensate with equity + co-authorship, not consulting fees.
- **Regulatory writing firm**: white-label partner for IND narrative sections. BioMate prices the full package; firm gets subcontract. No headcount.
- **Academic collaborators with data**: PI as named NCATS grant PI; BioMate as computational core. Their patient data → BioMate's most valuable execution traces.

**Key discipline:** Every professional engagement must produce execution traces or model training data that lives in the platform permanently. If a project ends and nothing is added, it was consulting.

---

## 6. Sequenced Action Plan

### NOW (before August 20, 2026 — Arc VCC sprint)
- [ ] Register at **virtualcellchallenge.org** for Arc Virtual Cell Challenge 2026 (opens Aug 20)
- [ ] Download **Tahoe-100M** pretraining data: 100M cells, CC0 license, HuggingFace — better than CellxGene alone
- [ ] Download **Replogle 2022** Perturb-seq (BioProject PRJNA831566) as secondary training set
- [ ] Download H1 hESC challenge dataset (300K cells, 300 CRISPRi perturbations) when released Aug 20
- [ ] **2025 winner strategy to replicate:** hybrid statistical + neural baseline — LSTM/GRU/CNN with mean/std/percentile features; NOT a pure foundation model approach
- [ ] Target both Grand Prize AND Generalist Prize track (separate evaluation, separate $75K)
- [ ] Contact CZI Virtual Biology Initiative (virtualbiology@biohub.org) re: $100M external grant program — parallel funding track
- [ ] Begin CyclicMPNN + RFdiffusion integration into BioMate drug discovery pipeline (2–4 weeks)
- [ ] Curate macrocycle ADMET dataset: ChEMBL + PermSMR + published Pfizer/AZ macrocycle series

### Phase 1: Revenue + Foundation (Months 1–3)
- [ ] Approach 3–5 pharma/biotech companies post-Phase 2 failure with biomarker stratification service (Direction 1) — elastic net pipeline, $75K–$150K per project
- [ ] Download CellxGene immune atlas + run 100 autoimmune GEO datasets through BioMate on AWS Batch
- [ ] ~~Run all curatedMetagenomicData samples through BioMate metagenomics pipeline~~ **REMOVED — microbiome direction dropped**
- [ ] Identify 2–3 academic KOLs in Sjögren's/SSc with patient registries for SAB + NCATS co-application
- [ ] Run IL-17A cyclic peptide pilot: RFdiffusion → CyclicMPNN → AlphaFold3 docking → macrocycle ADMET → PBPK

### Phase 2: Model Training + Grant (Months 3–6)
- [ ] Submit Arc VCC entry (challenge likely runs Oct–Dec 2026 with final leaderboard)
- [ ] Train Macrocycle ADMET Predictor on curated dataset; benchmark against ADMETlab/SwissADME on macrocycle-specific test set
- [ ] ~~Train microbiome intervention classifier~~ **REMOVED**
- [ ] Submit NCATS RFA-TR-25-002 application (Sjögren's + SSc, TYK2 + IRF5 anchors, academic PI co-applicant)
- [ ] Integrate PK-Sim wrapper for PBPK modeling (enables Direction 2 + cyclic peptide IND packages)
- [ ] Identify regulatory writing firm as white-label IND package partner

### Phase 3: Commercial Product + Moat (Months 6–18)
- [ ] Launch IND package service (Direction 2) with regulatory writing partner — now includes cyclic peptide design → ADMET → PBPK → narrative
- [ ] Train Drug-Immune Perturbation Predictor on LINCS CMap + OP3 data
- [ ] Publish: (a) Arc VCC results paper, (b) Macrocycle ADMET benchmark vs existing tools
- [ ] NCATS grant award (~Month 9–12) funds continued rare disease model development
- [ ] Build cross-disease target ranker: integrates GWAS signal + immune perturbation predictions + druggability scores

---

## 7. Key Business Metrics

| Metric | What to track | Why |
|---|---|---|
| Revenue per project | $ per completed engagement | Core unit economics |
| AWS Batch cost per run | $ infrastructure per workflow execution | Must survive 30% inference price increase |
| 90-day retention | % labs/companies running 2nd project | Proves habit, not one-shot |
| Execution traces per month | New proprietary runs added to memory | Measures data moat growth rate |
| Procedural memory entries | Learned procedures tagged by domain | Measures platform self-improvement rate |
| Cross-team runs | Projects where 2+ teams use same workflow | Network effect signal |
| Pipeline → publication | Projects producing a paper or IND filing | Proof of scientific value |

---

## 8. Competitive Moat Summary

| Moat layer | What it is | Time to replicate |
|---|---|---|
| Workflow library | 2,455 pre-validated workflows | 12–18 months |
| Execution traces | Proprietary runs on real autoimmune + microbiome data | Cannot replicate without same data access |
| Procedural memory | Disease-specific parameter knowledge from every run | Compounds — grows with every run |
| Specialized models | Immune perturbation predictor, microbiome classifier | 18–24 months without the training data |
| Academic network | Co-authorship relationships with KOLs + rare disease data access | Relationship-based, not replicable by funding alone |

---

## 9. Open Questions

1. **Self-evolving harness**: automatic lesson extraction from workflow failures (e.g., Entrez→symbol conversion requirement) into procedural memory — currently manual, should be automated. Plan to be developed separately.
2. **Microbiome-autoimmune intersection**: gut dysbiosis in RA/IBD/SLE — this may be a stronger unified model direction than treating them as separate domains.
3. **GALARISSO topline (Dec 2025)**: TYK2 inhibitor results in dermatomyositis — if positive, dramatically strengthens the TYK2 anchor for Sjögren's/SSc grant application.
4. **Longevity timing**: 12-month window before Altos/Calico publish foundation models — revisit in Q4 2026.
