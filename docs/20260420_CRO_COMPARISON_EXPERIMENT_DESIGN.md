# BioMate vs. Traditional CRO: Experiment Design and Tech Report Protocol
**Date**: 2026-04-20  
**Authors**: BioMate Research Team  
**Target venue**: ChemRxiv preprint → Journal of Cheminformatics or J. Chem. Inf. Model.

---

## 1. The Core Question

> **Can a computational-first AI platform (BioMate) replicate the compound prioritization decisions of a traditional wet-lab CRO, at a fraction of the cost and cycle time, with regulatory-grade audit trails?**

This is not a "AI is better than wet lab" claim — that would be unpublishable and wrong. It is a more precise and defensible claim:

> **In the Bayesian optimization phase of early drug discovery (hit-to-lead), BioMate's active learning loop produces compound proposals that achieve [X]% of the hit rate of traditional cascade screening, in [Y]× fewer days, with [Z]× lower cost per validated hit.**

Secondary claims:
- BioMate's PBPK predictions meet the EMA 67%-within-2-fold qualification criterion on a 31-drug reference set
- BioMate's ADMET models meet published benchmark accuracy for hERG (AUROC ≥ 0.84, Cai et al. 2019), DILI (AUROC ≥ 0.73, DILIrank benchmark), and Ames mutagenicity (AUROC ≥ 0.82, Kazius et al. 2005)
- BioMate's Bayesian optimization loop converges to a top-5% compound in ≤ 3 rounds when the virtual library contains the ground-truth active, demonstrating prospective utility

---

## 2. Study Design Options

### Option A — Retrospective Benchmark (Recommended for initial publication)

**What**: Run BioMate against published drug discovery datasets where both the virtual library AND the ground-truth experimental activities are known. Simulate 3 rounds of DMTA using BioMate's Bayesian optimizer. Compare against three baselines.

**Why first**: Fully reproducible. No CRO needed. Publishable in 4–8 weeks.

**Datasets** (all public, with experimental activity data):

| Dataset | Source | Compounds | Assay type | Relevance |
|---------|--------|-----------|-----------|-----------|
| **ExCAPE-DB** | Gaulton et al., 2017 | 998,000 compounds, 10M+ activity data points | IC50, EC50 against 1,000+ targets | Virtual library simulation |
| **MoleculeNet ADMET** (Tox21, ClinTox, SIDER, HIV) | Wu et al., 2018 | 10K–12K | Binary bioactivity, toxicity | ADMET prediction benchmark |
| **AstraZeneca-Sanofi Lipophilicity** | Wenlock et al. | 4,200 compounds | logD7.4 (measured) | PBPK/ADMET |
| **ChEMBL EGFR dataset** | Gaulton et al. | 17,000 compounds | IC50 (Km-corrected) | Complete DMTA simulation |
| **Merck ADMET benchmark** | Brown et al., J. Chem. Inf. Model. 2022 | ~5,000 | 20+ endpoints (CRO-grade) | CRO-quality ADMET data |
| **DRD2 active learning benchmark** | Renz et al., ACS Cent. Sci. 2019 | 340K virtual library | Docking score proxy → validated IC50 | Active learning comparison |
| **DILI benchmark (DILIrank)** | Chen et al., Hepatology 2016 | 1,036 drugs | Clinical DILI outcome | Hepatotoxicity claim |

**Protocol for each target**:
1. Extract the full experimental activity table from ChEMBL for one well-characterized target (EGFR, JAK2, or BACE1 — all have >3,000 IC50 measurements)
2. Split: 5% "seed compounds" (given to BioMate as initial ranked list), 95% held as ground truth
3. Run 3 simulated DMTA rounds:
   - Round N: BioMate proposes 10 compounds from virtual library
   - Oracle: look up ground-truth IC50 for proposed compounds, return as "assay results"
   - Auto-retrain loop: ingest oracle results, refit GP, propose Round N+1
4. After 3 rounds (30 proposals), compute enrichment metrics vs. baselines

**Baselines**:
- **Random screening**: 30 randomly selected compounds from virtual library
- **Similarity search**: 30 compounds most similar (Tanimoto) to seed compounds
- **Commercial ML** (if available): Schrödinger FEP+ or Glide docking score ranking

### Option B — Prospective Micro-Study

**What**: Partner with a synthesis provider (Enamine, Sigma-Aldrich building blocks, or a university synthetic chemistry group). BioMate proposes 20–50 novel SMILES from a real virtual library. Partner synthesizes 5–10 of the top-ranked compounds. Assay results measured (IC50, ADMET).

**Why**: Real experimental validation. High impact claim. Required for top-tier journals.

**Cost estimate**: ~$20,000–$50,000 (synthesis + assay). Timeline: 3–6 months.

**Target**: One well-characterized tractable protein. Recommended: BACE1 (Alzheimer's), CDK2 (oncology), or Mpro (antiviral — structural data abundant).

**Protocol**:
1. Obtain crystal structure or homology model
2. Run Glide/GNINA docking on Enamine REAL library subset (100K compounds)
3. Use docking scores as initial ADMET-unfiltered scores → seed BioMate
4. BioMate proposes top-10 after ADMET filtering
5. Send top-10 to synthesis CRO (Enamine synthesis service: ~$800–1200/compound)
6. Assay: SPR binding + cell-free IC50 (can be done at academic core facility ~$200/compound)
7. Results fed back into BioMate → Round 2 proposal → repeat 2–3 rounds

### Option C — Parallel-Run Comparison (Most rigorous, for flagship paper)

**What**: Engage a small CRO (WuXi AppTec, Pharmaron, or Evotec) to run a real DMTA campaign on the same target simultaneously with BioMate. Compare proposals after each round without cross-contamination.

**Why**: Direct apples-to-apples comparison with a named CRO. Publishable in Nature Chemical Biology or J. Med. Chem.

**Cost**: $150,000–$500,000. Timeline: 6–12 months.

**Note**: Requires CRO NDA, IP agreements, and IRB waiver (for non-clinical work, typically straightforward).

---

## 3. Metrics Framework

### 3.1 Primary metrics — Compound Prioritization

| Metric | Formula | Target | Reference |
|--------|---------|--------|-----------|
| **Hit Rate (HR)** | `n_active_proposed / n_proposed` | BioMate ≥ 2× random | Standard in virtual screening |
| **Enrichment Factor (EF₅)** | `HR_top5% / HR_random` | EF₅ ≥ 3.0 | Truchon & Bayly, J. Chem. Inf. Model. 2007 |
| **BEDROC α=20** | Boltzmann-enhanced discrimination of ROC | BEDROC ≥ 0.7 | Truchon & Bayly 2007 |
| **Cumulative active recovery** | `n_actives_found / round` | ≥ 60% actives in top 30 proposals | Active learning standard |
| **Rounds to first hit** | `min(round)` where a ≥ threshold compound is proposed | ≤ 2 rounds | Active learning standard |

### 3.2 PBPK/PK accuracy

| Metric | Target | Reference |
|--------|--------|-----------|
| **Within-2-fold fraction (Cmax)** | ≥ 67% | EMA/CHMP/EWP/37498/2011 |
| **Within-2-fold fraction (AUC)** | ≥ 67% | EMA/CHMP/EWP/37498/2011 |
| **AAFE (Cmax)** | ≤ 2.0 | Sheiner & Beal, J. Pharmacokinet. Biopharm. 1981 |
| **AAFE (AUC)** | ≤ 2.0 | Sheiner & Beal 1981 |
| **R² (Cmax)** | ≥ 0.60 | EMA PBPK guideline |

### 3.3 ADMET model accuracy

| Endpoint | Metric | Target | Benchmark reference |
|----------|--------|--------|-------------------|
| **hERG inhibition** | AUROC | ≥ 0.84 | Cai et al., Mol. Inform. 2019 |
| **DILI** | AUROC | ≥ 0.73 | Chen et al., Hepatology 2016 (DILIrank) |
| **Ames mutagenicity** | AUROC | ≥ 0.82 | Kazius et al., J. Med. Chem. 2005 |
| **CYP3A4 inhibition** | AUROC | ≥ 0.80 | Veith et al., Nat. Biotechnol. 2009 |
| **BBB penetration** | AUROC | ≥ 0.85 | Martins et al., J. Chem. Inf. Model. 2012 |
| **Aqueous solubility (logS)** | RMSE | ≤ 1.0 log unit | Delaney benchmark (ESOL) |

### 3.4 Operational efficiency (for CRO comparison)

| Metric | BioMate | Traditional CRO | Delta |
|--------|---------|----------------|-------|
| **DMTA cycle time** | Hours (computation) | 4–8 weeks (synthesis + assay) | 50–500× |
| **Cost per compound evaluated** | ~$0.01 (compute) | $1,200–$3,000 (synthesis + assay) | 100,000× |
| **Cost per hit identified** | TBD | $50,000–$500,000 | TBD |
| **Proposal throughput** | 10 compounds/round | 10–50 compounds/round | ~comparable |
| **Regulatory audit trail** | ✅ 21 CFR Part 11 hash chain | Paper-based or proprietary LIMS | BioMate advantage |
| **Reproducibility** | Full audit log, git-committed parameters | Often proprietary and opaque | BioMate advantage |

**Important nuance for the paper**: The cost comparison is valid for the *in silico screening phase* only. BioMate does NOT replace synthesis or wet-lab assays — it reduces the number of synthesis/assay cycles needed by better prioritizing which compounds to make.

---

## 4. Statistical Analysis Plan

### 4.1 Bootstrap confidence intervals
For all classification metrics (AUROC, EF, HR):
- Bootstrap 1,000 samples from the test set
- Report [5th, 95th] percentile interval
- Two-sided Mann-Whitney U test for BioMate vs. each baseline

### 4.2 Active learning convergence analysis
For the DMTA simulation:
- Run 10 independent seeds (different random 5% initial splits)
- Plot mean ± SD of cumulative active recovery vs. round number
- Compare convergence curves between BioMate, similarity search, and random

### 4.3 Power analysis (for prospective study, Option B)
To detect EF₅ ≥ 3.0 with α = 0.05, power = 0.80:
- Estimated n = 50–100 proposed compounds (Fisher's exact test on hit rate)
- Justification: if random hit rate is 1% (typical for lead-like screening), need ≥ 3% hit rate in BioMate proposals to detect with sufficient power

### 4.4 Reproducibility
- All BioMate runs version-controlled (git commit hash in Methods)
- All ChEMBL data downloaded with version tag (ChEMBL 33, February 2024)
- Random seeds fixed and reported
- Bayesian optimizer `n_initial`, `diversity_weight`, fingerprint parameters all reported

---

## 5. Data Preparation Protocol

### 5.1 ChEMBL extraction (for DMTA simulation)

```python
# Target: EGFR (CHEMBL203)
# Filter: IC50, exact measurement, human or human cell-line assay
# Curate: remove duplicates, standardize SMILES (RDKit), remove salts
# Normalize: pIC50 = -log10(IC50_M)
# Active threshold: pIC50 ≥ 7.0 (IC50 ≤ 100 nM)
# Split: random 5% seed, 95% oracle

# Virtual library: Enamine REAL Drug-Like subset (1.2M compounds)
# Alternatively: ChEMBL actives + 50× decoys from DUD-E
```

### 5.2 ADMET benchmark datasets

Download from MoleculeNet (https://moleculenet.org/datasets-1):
- `tox21.csv` — 12K compounds, 12 toxicity endpoints
- `clintox.csv` — 1,478 compounds, clinical trial toxicity outcomes
- `sider.csv` — 1,427 drugs, 27 adverse effect endpoints
- `hiv.csv` — 41,127 compounds, anti-HIV activity

Download DILIrank from Chen et al. Hepatology 2016 supplementary:
- 1,036 drugs, DILI outcome (DILI concern / no DILI concern)

Download Ames dataset from Kazius et al. 2005 supplementary:
- 4,337 compounds (2,401 mutagens, 1,936 non-mutagens)

### 5.3 PBPK reference dataset

Already in BioMate: `backend/lib/galaxy/ai/drug_discovery/reference_data/pk_marketed_drugs.json`  
- 31 marketed drugs with measured Cmax, AUC, CL, Vd, F
- Clopidogrel excluded (prodrug, CL_true physiologically impossible)
- All values sourced from FDA approved labels and DrugBank

---

## 6. Tech Report Structure

### Recommended format: ChemRxiv preprint → J. Chem. Inf. Model.

**Title options**:
- *"BioMate: An AI-Native Computational CRO Platform for Bayesian-Guided Drug Discovery with 21 CFR Part 11-Compliant Audit Trails"*
- *"Active Learning-Driven DMTA Loops for Early Drug Discovery: A Computational CRO Evaluation Against Experimental Benchmarks"*
- *"From Virtual Library to IND Submission: A Validated AI Platform for Computational Drug Discovery"*

---

### 6.1 Abstract (250 words)

Structure:
1. **Problem** (2 sentences): Traditional DMTA cycles are slow (4–8 weeks/round) and expensive ($1,200–$3,000/compound). Computational CRO platforms promise to accelerate this, but rigorous validation against experimental benchmarks is absent from the literature.
2. **Method** (3 sentences): Describe BioMate, the Bayesian optimizer, and the benchmark design.
3. **Results** (3–4 sentences): EF₅, hit rate, ADMET AUROC, PBPK within-2-fold.
4. **Conclusion** (2 sentences): What BioMate can and cannot replace. Reproducibility statement.

---

### 6.2 Introduction

**Sections**:
1. Drug discovery cost crisis ($2.5B per approved drug; Wouters et al., JAMA 2020)
2. DMTA loop and its computational acceleration potential
3. CRO landscape: what traditional CROs do, where computational tools have been applied
4. Gap: no AI platform has been validated end-to-end from virtual screening → IND-ready documentation with auditable regulatory compliance
5. BioMate contribution: describe the three phases + what this paper evaluates

**Key citations**:
- Wouters et al., JAMA 2020 (drug development cost)
- Schneider et al., Nat. Rev. Drug Discov. 2020 (AI in drug discovery)
- Coley et al., Science 2020 (autonomous drug discovery)
- Pyzer-Knapp et al., Annu. Rev. Mater. Res. 2022 (active learning in chemistry)
- EMA PBPK guideline EMA/CHMP/EWP/37498/2011 Rev1

---

### 6.3 Methods

#### A. BioMate Platform Description
- Architecture: FastAPI backend, React frontend, SQLite compliance DB, AWS Batch execution
- Key modules: `model_validation.py`, `applicability_domain.py`, `bayesian_optimizer.py`, `auto_retrain.py`, `ind_assembly.py`, `audit_store.py`, `esig.py`
- GitHub: (link to open-source repository)
- Version: commit hash (for reproducibility)

#### B. PBPK Model

Describe `_AnalyticalPKPredictor`:
- 1-compartment model
- ke formula for oral drugs: `ke = CL_apparent × F / Vd` (Wagner 1993)
- AUC formula: `AUC = dose / CL_apparent` (Rowland & Tozer 2011)
- Cmax: Bateman equation `Cmax = (F·D/Vd) × ka/(ka-ke) × [exp(-ke×tmax) - exp(-ka×tmax)]`
- ka estimated from logP (empirical rules; ±20% error acknowledged as limitation)
- Validation dataset: 31 marketed drugs (DrugBank + FDA labels); Clopidogrel excluded (CYP2C19 prodrug)

#### C. ADMET Models

List which models are used and their source:
- hERG: (name the model, AUROC on held-out set)
- DILI: (model, AUROC on DILIrank)
- Ames: (model, AUROC on Kazius dataset)
- Report gate thresholds used in BioMate and their literature justification

#### D. Applicability Domain

- Hat-matrix leverage: `h_i = x^T (X^T X)^+ x`; threshold `h* = 3 × mean(h_train)` (Tropsha 2010)
- Tanimoto guard: OOD if max similarity to training < 0.20 (Bajusz et al. 2015)
- Both criteria must pass
- Report: fraction of validation compounds in-domain; fraction of proposals in-domain

#### E. Bayesian Optimization

- GP kernel: Matérn 5/2 (or whatever sklearn uses)
- Acquisition function: Expected Improvement
- Fingerprint: Morgan radius 2, 2048 bits
- `n_initial`, `diversity_weight` reported per experiment

#### F. DMTA Simulation Protocol

Exact reproduction steps:
1. Seed set selection (random 5%, fixed seed)
2. Oracle setup (ChEMBL IC50 lookup)
3. Virtual library: describe source and preprocessing
4. Round structure: 10 proposals per round, 3 rounds
5. Auto-retrain trigger: after each oracle batch
6. Active threshold: pIC50 ≥ 7.0

#### G. Baselines

1. **Random screening**: uniform random sampling from virtual library (10 per round, 1,000 bootstrap reps)
2. **Tanimoto similarity screening**: top-K by Tanimoto to seed set centroid
3. **Single-pass Bayesian** (no auto-retrain): fit once on seed, no updates

#### H. Statistical Analysis

As described in Section 4.

#### I. Regulatory Compliance Implementation

- Audit store: SHA-256 hash chain, `PRAGMA synchronous = FULL`, `BEGIN IMMEDIATE` atomic appends (ref: Haber & Stornetta, J. Cryptology 1991)
- TOTP eSig: RFC 6238, HMAC-SHA1, 30-second window
- IND assembly: ICH M4 CTD §2.6.1 structure
- All regulated actions (assay ingest, CRO export, IND generation) logged immutably

---

### 6.4 Results

#### Section 1: PBPK Model Qualification

**Figure 1** — Parity plot: predicted vs. observed Cmax and AUC (log-log scale, unity line, 2-fold envelope shaded).
- One panel for Cmax, one for AUC
- Points colored by drug class (cardiovascular, CNS, anti-infective, etc.)
- Clopidogrel labeled as excluded with explanation
- EMA criterion banner: "X% within 2-fold (≥67% required)"

**Table 1** — Aggregate validation metrics:
- Columns: metric, Cmax value, AUC value
- Rows: AFE, AAFE, R², within-2-fold (%), within-3-fold (%)

**Supplementary Table S1** — Per-compound results (all 31 drugs, or 30 after Clopidogrel exclusion).

#### Section 2: ADMET Benchmark

**Figure 2** — ROC curves for each ADMET endpoint (hERG, DILI, Ames, CYP3A4).
- Overlay BioMate curve (solid) vs. published best-in-class (dashed)
- AUROC values annotated on each panel

**Table 2** — ADMET benchmark summary:
- Columns: endpoint, dataset, n_compounds, BioMate AUROC [95% CI], published benchmark AUROC, reference

#### Section 3: Bayesian Optimization Simulation (DMTA Loop)

**Figure 3** — Cumulative active recovery curves (mean ± SD across 10 seeds):
- X-axis: DMTA round (0–3), Y-axis: fraction of top-5% actives recovered
- Lines: BioMate (with auto-retrain), Single-pass Bayesian, Similarity search, Random
- Shaded regions: SD

**Figure 4** — Enrichment factors by method (grouped bar chart):
- Groups: Random, Similarity, Single-pass Bayesian, BioMate
- Bars: EF₁ (top 1%), EF₅ (top 5%), EF₁₀ (top 10%)

**Table 3** — Statistical comparison:
- BioMate vs. each baseline: EF₅, Hit Rate, Mann-Whitney U p-value

**Target-specific results**: Run on ≥3 targets (e.g. EGFR, JAK2, BACE1) to show generalizability.

#### Section 4: Applicability Domain Coverage

**Table 4** — AD analysis summary:
- Reference set: % in-domain (training compounds trivially in domain)
- ADMET benchmark test set: % in-domain; AUROC conditioned on in-domain vs. OOD
- Bayesian proposals: % in-domain per round (hypothesis: later rounds should increase in-domain fraction as loop learns)

#### Section 5: Regulatory Compliance Infrastructure

This section distinguishes BioMate from pure research tools.

**Table 5** — 21 CFR Part 11 compliance feature matrix:
| Requirement | §11.10 subsection | BioMate implementation | Verified by |
|------------|------------------|----------------------|-------------|
| Audit trails | §11.10(e) | SHA-256 hash chain, WAL SQLite | `test_verify_chain_detects_field_modification` |
| System access controls | §11.10(d) | JWT Bearer + eSig gate | (test ID) |
| Electronic signatures | §11.200(a) | TOTP RFC 6238, replay protection | `test_esig_replay_protection` |
| Record integrity | §11.10(a) | `BEGIN IMMEDIATE` atomic append, `synchronous=FULL` | `test_concurrent_appends_produce_valid_chain` |
| Closed system controls | §11.10(c) | Immutable audit log (no UPDATE/DELETE) | (test ID) |

**Supplementary Material**: Reproduce a full sample audit trail export (anonymized) showing the hash chain for a 3-round DMTA campaign.

---

### 6.5 Discussion

**What BioMate does better than a traditional CRO (in the in silico phase)**:
- Cycle time: hours vs. weeks
- Cost of each proposal round: negligible compute cost vs. $12,000–30,000 synthesis batch
- Regulatory documentation: automated, auditable vs. manual laboratory notebooks

**What a traditional CRO still does that BioMate cannot**:
- Actual synthesis
- Biophysical binding assays (SPR, ITC, X-ray crystallography)
- Cell viability and selectivity profiling
- In vivo ADME (clearance in hepatocytes, plasma protein binding by equilibrium dialysis)

**The intended model**: BioMate runs the computational DMTA rounds. The wet-lab CRO validates the shortlist. Total rounds needed drops from 6–10 (CRO-only cascade) to 1–2 (BioMate-filtered synthesis batch). This is the productivity claim.

**Limitations**:
- PBPK model uses estimated ka from logP (±20% Cmax error); validated only for oral small molecules
- Bayesian GP uses Morgan fingerprints (2048-bit, radius 2); macrocycles and highly flexible scaffolds may underperform
- Applicability domain: Tanimoto threshold 0.20 is conservative; some valid predictions may be OOD-flagged
- ADMET models have not been validated for novel chemical space beyond the training distribution
- The 31-drug PBPK validation set is general (not target-class specific); disease area–specific validation is future work

**Comparison to published AI drug discovery platforms**:
- Insilico Medicine's Chemistry42 (Ren et al., Nature Biotechnology 2022): shows active learning, no 21 CFR compliance, no PBPK
- Recursion Pharmaceuticals: phenotypic screening, not DMTA loop
- Schrödinger LiveDesign: FEP+-based, requires proprietary force fields
- BioMate differentiator: open-source, regulatory-grade audit trail, integrated IND assembly, PBPK qualification

---

### 6.6 Conclusion

Three-paragraph conclusion:
1. Performance summary (hit rates achieved, EMA criterion met, ADMET benchmark results)
2. Regulatory compliance as a novel contribution (no published AI drug discovery platform has demonstrated 21 CFR Part 11 compliance infrastructure at this level)
3. Future work: prospective Option B/C study, addition of FEP for higher-accuracy predictions, validation in a specific therapeutic area

---

### 6.7 Data and Code Availability Statement

> All code is available at [GitHub URL]. BioMate version [X.Y.Z], commit [hash]. All benchmark datasets are publicly available at the URLs listed in the Supplementary Methods. The 31-drug PBPK reference dataset is provided as Supplementary Data 1. All experiment configurations and random seeds are provided in Supplementary Data 2. To reproduce all figures, run `python scripts/reproduce_paper_figures.py` after installing the dependencies listed in `requirements_paper.txt`.

---

## 7. Execution Timeline

### For Option A (Retrospective — recommend starting here)

| Week | Task | Owner |
|------|------|-------|
| 1 | Download and curate ChEMBL EGFR, JAK2, BACE1 datasets | Data eng |
| 1 | Download MoleculeNet ADMET datasets | Data eng |
| 2 | Implement DMTA simulation harness (oracle wrapper) | Backend eng |
| 2–3 | Run 10-seed Bayesian optimization benchmark on 3 targets | Backend eng |
| 3 | Run ADMET benchmark on MoleculeNet + DILIrank | Backend eng |
| 4 | Run PBPK validation (already done, generate paper-quality figures) | Backend eng |
| 4–5 | Generate all figures + tables | Research |
| 5–6 | Write manuscript | Research |
| 6–7 | Internal review + revision | All |
| 8 | Submit to ChemRxiv + J. Chem. Inf. Model. | Research |

### For Option B (Prospective — after Option A published)

| Month | Task |
|-------|------|
| 1 | Select target, obtain structure, set up docking pipeline |
| 1–2 | Screen Enamine REAL subset (100K), select seed compounds |
| 2 | BioMate Round 1 proposals (10 compounds) → send to synthesis |
| 3–4 | Synthesis (Enamine ~4–6 week turnaround) + assay |
| 4 | Ingest results, auto-retrain, Round 2 proposals |
| 5–6 | Round 2 synthesis + assay |
| 6–7 | Round 3 (if warranted) |
| 7–8 | Analysis + write-up |
| 8 | Submit to J. Med. Chem. |

---

## 8. The Claude Design Reference UI

The prototype in `/home/yzhang/biomate/reference/claude_design/cro/` (7 JSX surface components + design tokens) serves two functions in the tech report:

1. **Demonstration screenshots for the paper**: Each figure panel that shows the BioMate interface should be taken from the production-ported version of the Claude Design prototype. Specifically:
   - Figure 1 (PBPK validation) → `Surface2_ValidationPanel.jsx` ported screenshot
   - Figure 3 (Bayesian loop convergence) → data visualization but inset showing the `Surface4_AutoRetrain.jsx` proposal table
   - Table 5 (compliance feature matrix) → screenshot of `Surface3_AuditTrail.jsx` showing a real audit record with hash chain

2. **Supplementary demo video**: A 2-minute screen recording showing the end-to-end DMTA campaign flow in the BioMate UI (using the ported Claude Design surfaces). Upload to ChemRxiv as supplementary video.

The prototype uses mock data (`data-cro.js`). For the paper demo, replace with real experiment data from the retrospective benchmark. The HANDOFF_CRO.md document in the reference directory specifies the porting path from JSX prototype to production TypeScript components.

---

## 9. Competitive Positioning in the Literature

The paper should cite and differentiate from:

| Platform | Reference | BioMate difference |
|----------|-----------|-------------------|
| Chemistry42 (Insilico) | Ren et al., Nat. Biotechnol. 2022 | BioMate: open-source, PBPK-qualified, 21 CFR audit |
| REINVENT (AZ) | Blaschke et al., J. Cheminform. 2020 | BioMate: active learning vs. generative; integrated DMTA loop |
| DeepChem | Ramsundar et al., MIT Press 2019 | BioMate: clinical workflow integration, regulatory docs |
| AutoML-Zero | Real et al., ICML 2020 | Different domain — mention only for context |
| AtomNet (Atomwise) | Wallach et al., arXiv 2015 | BioMate: broader than docking; Bayesian loop |
| GENTRL | Zhavoronkov et al., Nat. Biotechnol. 2019 | BioMate: validation-first vs. generative-first |

**The strongest novel claim in the literature**: No published platform has demonstrated end-to-end computational CRO functionality (virtual screening → ADMET → PBPK → Bayesian loop → regulatory-grade audit trail → IND assembly) with open-source code and quantitative benchmarking against established regulatory criteria.

---

## 10. Quick-Start: Running the Retrospective Benchmark Now

To begin immediately without waiting for wet-lab work:

```bash
# 1. Download ChEMBL EGFR dataset
python scripts/download_chembl.py --target CHEMBL203 --endpoint IC50 --output data/egfr_chembl.csv

# 2. Download Enamine REAL Drug-Like virtual library (or use public subset)
# Available at: https://enamine.net/compound-collections/real-compounds/real-database

# 3. Run DMTA simulation (3 rounds, 10 seeds)
python scripts/run_dmta_simulation.py \
  --activity-file data/egfr_chembl.csv \
  --virtual-library data/enamine_drug_like.smi \
  --n-rounds 3 \
  --n-propose 10 \
  --n-seeds 10 \
  --output results/egfr_dmta/

# 4. Run ADMET benchmark
python scripts/run_admet_benchmark.py \
  --datasets tox21,clintox,sider,hiv,dilirank,ames \
  --output results/admet_benchmark/

# 5. Generate figures
python scripts/make_paper_figures.py \
  --dmta-results results/egfr_dmta/ \
  --admet-results results/admet_benchmark/ \
  --pbpk-report backend/lib/galaxy/ai/drug_discovery/reference_data/pk_marketed_drugs.json \
  --output figures/
```

Scripts `run_dmta_simulation.py` and `run_admet_benchmark.py` are not yet implemented — this is the primary engineering task for Option A. The DMTA simulation requires a thin oracle wrapper around the existing BioMate `BayesianOptimizer` and `AssayIngestionService`. Estimated implementation time: 2–3 days.
