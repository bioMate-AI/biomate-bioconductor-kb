# Drug-Development Benchmark Landscape Survey + BioMate Drug-Dev Benchmark Series Design

**Date:** 2026-10-21 (v2 — expanded after a deeper, three-pass survey)
**Status:** survey + design. Grounds a new drug-development benchmark series + manuscript, parallel to RealBio.
**Inputs:** three exhaustive, primary-source benchmark surveys (≈165 entries across agents/target/search/knowledge, structure–activity, and property/ADMET/tox/PK/synthesis/trials); an internal audit of BioMate's drug-dev evals (B1–B5) + workflows; the RealBio packaging template.

**Confidence tags** carried from the surveys: **[C]** primary-source confirmed this pass; **[C2]** confirmed secondary (consistent across sources, PDF not opened); **[U]** unverified (named, not re-fetched — verify before external citation). Counts on [C2]/[U] entries are approximate.

---

## 0. Executive summary — what changed from v1, and the thesis

v1 over-indexed on tool/execution workflows and under-covered the rest. The deeper survey corrects three things:

1. **Target-discovery, perturbation, search, and knowledge tasks are *well* benchmarked externally** (BioDiscoveryAgent, GEARS, Arc Virtual Cell Challenge, GenoTEX, CRISPR-GPT; Open Targets, PrimeKG, DrugMechDB, TxGNN; PaperQA2, STaRK-PRIME, LitQA2; ChemBench, MoleculeQA, GPQA). These are **not** BioMate white space — the series should include them as tracks and *position against* these baselines, not claim to invent them.
2. **The real methodological frontier is leakage control and metric integrity** — LP-PDBBind, CleanSplit/GEMS, PLINDER/PINDER, Runs-N-Poses, DockGen, BayesBind, plus explicit bias critiques of DUD-E/LIT-PCBA, and the "Beyond Affinity" finding that Vina-as-reward is *gameable*. Any new benchmark that does not bake in leakage-aware splits and reward-hacking-resistant metrics is obsolete on arrival.
3. **The genuine white space is narrower and sharper than "drug-dev":** execution-grounded **end-to-end** and **cross-stage** pipelines (no external benchmark grades these), plus a short list of confirmed single-stage gaps (PBPK-ML, dose-from-real-data, formulation/stability/CMC, FTO/IP, ABFE, antibody affinity+developability). That is what BioMate's series should own.

**Thesis for the series + paper:** the first **execution-grounded, cross-stage** drug-development benchmark — grading real pipeline runs and multi-stage reasoning with leakage-aware, reward-hacking-resistant design — positioned honestly against a rich existing single-stage/agent landscape where frontier LLMs are strong at some stages (ligand ranking, knowledge QA) and near-useless at others (PBPK, dose).

---

## 1. The landscape (survey)

### 1.A Agent / agentic science & drug-discovery benchmarks (the comparison set)

| Benchmark | Tests | Scale | Conf |
|---|---|---|---|
| **Biomni / Biomni-Eval1** | general biomedical agent (plan+tool+code), 10 subtasks / 25 domains | — | [C] |
| **TxAgent + ToolUniverse** | therapeutic reasoning over 211 tools; ships DrugPC/BrandPC/GenericPC/TreatmentPC/DescriptionPC | 3,168 + 456 tasks | [C] |
| **TxGemma / Agentic-Tx** | therapeutics LLM (2/9/27B) + agent wrapper; eval on 66 TDC tasks | — | [C2] |
| **DMPKBench** | LLM/agent DMPK reasoning (design/interp/ADMET-MPO/PK/translation) | >100k QA | [C] |
| **TxBench-PP** (Latch) | verifiable preclinical-pharmacology agent endpoints | 100 evals / ~300 endpoints | [C] |
| **DrugAgent** (3 distinct papers — disambiguate) | DTI/repurposing multi-agent; ADMET ML-coding agent | — | [C] |
| **ChemCrow / Coscientist** | chemistry tool-agent / autonomous robotic chemist | demo-scale | [C2] |
| **ChemToolAgent (+ChemToolBench)** | tool selection + parameter filling for chem agents | — | [C] |
| **BixBench** | real bioinformatics notebook analysis by agents | 296 Q / 53 capsules | [C] |
| **ScienceAgentBench** | data-driven discovery as self-contained Python | 102 tasks / 44 papers | [C] |
| **DiscoveryWorld** | end-to-end discovery in a sim world | 120 instances | [C] |
| **MLAgentBench / DSBench / DA-Code** | ML-/data-science research agents | 13 / 540 / ~500 tasks | [C] |
| **CORE-Bench / PaperBench / MLE-bench / RE-Bench / SciCode** | reproducibility & ML-research agents | 270 / — / 75 / — / — | [C]/[U] |
| **AAAR-1.0 / ResearchBench / SciArena** | expert research tasks / hypothesis / arena | — | [C] |
| **MedAgentBench / MedAgentsBench** | EHR-FHIR agent / clinical-reasoning agent frameworks | 100 / 862 | [C] |
| **LAB-Bench** | practical biology research skills (8 cats, incl. ProtocolQA/SeqQA/DbQA) | ~2,457 Q | [C] |

### 1.B Early-stage / target discovery & functional genomics

- **BioDiscoveryAgent** [C] — closed-loop genetic-perturbation experiment design; eval over 6 Perturb-seq datasets (Stanford/Arc, ICLR 2025).
- **GenoTEX / GenoMAS** [C] — automated gene-expression analysis for disease-gene ID; 1,384 problems / 913 datasets / 132 traits.
- **GEARS** [C] — predict transcriptional outcomes of novel (combo) perturbations (Stanford, Nat Biotech 2023).
- **PerturBench** [C] / **scEval** [C] / **scPerturb** [U] / **Open Problems in Single-Cell** [U] — single-cell perturbation/model-eval suites.
- **Arc Virtual Cell Challenge (2025)** [C] — predict perturbation effect in a held-out cell type; 300 perturbations / 300k cells (context generalization).
- **CRISPR-GPT** [C] — multi-agent gene-editing design copilot; 288-case "Gene-editing Bench."
- **Open Targets** [U] (de-facto gene–disease/target-prioritization ground truth — *no single canonical leaderboard*), **PrimeKG** [C] (129k nodes/4.05M edges), **DrugMechDB** [C] (4,583 indications), **TxGNN** [U] (zero-shot repurposing over a KG).

### 1.C Search / retrieval / literature

- **PaperQA2** [C] (lit-search+synthesis agent), **LAB-Bench/LitQA2** [C], **STaRK / STaRK-PRIME** [C] (retrieval over PrimeKG), **MIRAGE + MedRAG** [C] (7,663 Q medical RAG), **BioASQ** [U], **SciFact** [U], **PubMedQA** [U], **TREC-COVID / Clinical-Trials** [U].

### 1.D Knowledge / reasoning QA

- Biomed/clinical: **MedQA** (12,723) [U], **MedMCQA** (~194k) [U], **MMLU** med/bio/chem subsets [U], **MedBullets** [U], **MultiMedQA** [U], **HealthBench** (5,000 convos, 48,562 rubrics; OpenAI 2025) [C], **SciEval** (~18k) [C], **SciQ** [U].
- Chem/molecular: **ChemBench** (>2,700 Q; Nat Chem 2025) [C], **MoleculeQA** (62k over 23k mols) [C], **SMolInstruct/LlaSMol** (14 tasks) [C], **ChemLLMBench** [U].
- Cross-domain: **GPQA** (448/198) [C], **HLE** [U]. KG reasoning: **BioKGBench** (KGQA 698 + SCV 1,385 + KGCheck 225) [C].

### 1.E Technical — structure–activity

**DTI / binding:** DAVIS (30,056) [C2], KIBA (118,254) [C2], BindingDB (~1.6M curated) [C], BIOSNAP [C2], **DrugBAN leakage regimes** (random/cold-pair/cross-domain — AUROC collapses ~0.95→~0.65) [C], Human/C.elegans [U], **TDC DTI-DG** (temporal OOD by patent year) [C], MoleculeNet BACE (scaffold) [C2], PLATINUM (ΔΔG on mutation) [C2].

**Affinity + leakage control (the frontier):** PDBbind (v2020 ~19,443) [C2]; **LP-PDBBind** ⭐ (seq-id ≤0.5 + ligand Dice ≤0.99 splits; 11,513/2,422/4,860; BDB2020+ prospective) [C]; **CleanSplit + GEMS** ⭐ (TM-score>0.8 structure-based leakage removal; leakage-reliant models collapse) [C]; **MISATO** (19,443 + MD + QM) [C]; PLAS-5k [C]; **SAIR** (1.05M systems / 5.24M cofolded structures — largest) [C, split/license U]; Polaris/MoleculeACE Ki sets (activity-cliff stratified) [C]. **CASF-2016** scoring/ranking/docking/screening powers — *overlaps PDBbind training*, the leakage problem CleanSplit/LP fix [C].

**Docking / pose / co-folding:** **PoseBusters** ⭐ (RMSD≤2Å **and** PB-valid; post-2021 held-out; V2=308) [C]; **PLINDER** ⭐ (449,383 systems; protein+pocket+interaction+ligand-similarity leakage-aware splits) [C]; **PINDER** (protein-protein sister) [C]; Astex Diverse (85) [C]; **DockGen** ⭐ (unseen-pocket generalization) [C]; PoseCheck [C]; **CASP15/16 ligand** (prospective blind; lDDT-PLI + pose RMSD) [C]; **Runs N' Poses** ⭐ (2,600 post-cutoff; shows AF3/Boltz/Chai **memorize**, physics wins on novel) [C]; **PoseBench** (apo→holo, multi-ligand, blind) [C].

**Virtual screening (all have documented bias):** DUD-E (102 targets; known hidden bias) [C] + bias critiques [C]; DUDE-Z [C]; **LIT-PCBA** (15 targets, unbiased dose-response; 2025 leakage critique) [C]; MUV [C2]; DEKOIS 2.0 [C, counts U]; **BayesBind** ⭐ (2024, bias-resistant EF_B, structurally-dissimilar test targets) [C]; TOUGH-M1 [C, counts U].

**3D SBDD generation:** CrossDocked2020 (100k/100; 30%-seq-id split w/ residual pocket overlap) [C]; TargetDiff protocol [C]; **CBGBench** ⭐ (unifies SBDD as 3D-graph fill-in; 5 sub-tasks; substructure/chemical/interaction/geometry metrics) [C]; **PoseCheck** + **GenBench3D** (only 0–11% of generated mols have valid 3D conformations) [C]; **"Beyond Affinity"** ⭐ (Vina-as-reward is reward-hackable) [C]; Pocket2Mol/DiffSBDD/DecompDiff/MolCRAFT/DrugFlow (methods on CrossDocked) [C]; GEOM-Drugs / Binding MOAD as sets [C/U].

**Free-energy (FEP/RBFE/ABFE):** JACS-FEP / FEP+ (8 targets, 199 ligands) [C]; **Merck/Schindler FEP** (8 targets, 264 ligands; charge-changing) [C]; **OpenFF Protein-Ligand Benchmark** (21 targets) [C]; OpenFE (engine) [C]; FreeSolv (643, hydration) [C]. **ABFE: no canonical benchmark** — only SAMPL host-guest + scattered sets [U] → confirmed gap.

**Protein / biologics / fitness:** **ProteinGym** ⭐ (~291 DMS assays; CV folds for leakage) [C]; **Megascale stability** (776,298 ΔG) [C]; **SKEMPI 2.0** (7,085 ΔΔG on PPI mutation) [C]; **CASP14/15/16** + **CAMEO** (prospective blind) [C]; **FLIP** (fitness landscapes, designed splits) [C]; TAPE [C], PEER (17 tasks) [C]; **TAP + SAbDab** (antibody developability) [C]; CAPRI (blind PPI docking) [C]. Antibody affinity+developability is **fragmented — no unified leakage-controlled benchmark** [gap].

**Conformer / QM:** GEOM (450k mols/37M confs) [C], QM9/7/8 [C], MARCEL [C], Platinum conformers [C], PCQM4Mv2 (3.7M) [C], MD17/rMD17/MD22/SPICE (ML force fields) [C].

### 1.F Technical — property / ADMET / tox / QSAR / generation / retrosynthesis / PK / trials

**ADMET / property:** **TDC ADMET Group** ⭐ (22 datasets / 5 groups; the de-facto leaderboard) [C] + **TDC-2/PyTDC** [C]; **ADMET-AI** (Chemprop, tops TDC) [C]; **MoleculeNet** (17 sets) [C]; **Polaris Hub** [C]; OGB ogbg-mol* [U]; **ADMETlab 3.0** (119 endpoints) [C]; **OPERA** (OECD QSAR) [C]; **Biogen ADME** (industrial temporal split) [C]; **DeepDelta** (pairwise) [C]; **MARCEL** (conformers) [C]; **PharmaBench** (11 sets, ~156k) [U]. hERG/cardio: hERGCentral, BayeshERG, CardioTox [C/U].

**Toxicity:** Tox21 (12 assays) [U] + 2025 reproducible leaderboard [C]; ToxCast/ToxRefDB [U]; ClinTox [U]; **ToxBench** (8,770 ERα AB-FEP) [C]; **ProTox-3.0** (61 endpoints) [C]; **DILIrank** (1,336) / **DILIst** (1,279) [C]; Ames/Hansen (~6,512) [U]; CPDB carcinogenicity [U]; SIDER (1,427 × 27 ADR) [U].

**QSAR:** **MoleculeACE** ⭐ (30 targets, activity-cliff stratified) [C]; ChEMBL splits [U]; MUV [U]; TDC HTS [U].

**2D generation / optimization:** **GuacaMol** [U], **MOSES** (~1.9M) [U], **PMO** ⭐ (sample-efficiency, 23 oracles × 10k budget — modern standard) [C], **Tartarus** (physics-based) [C].

**Retrosynthesis / synthesizability:** USPTO-50k/-MIT/-full [U]; **PaRoutes** (2×10k routes) [C]; **Syntheseus** (fair re-eval framework) [C]; ORD [U]; **Buchwald-Hartwig** (3,955) [C] / **Suzuki** HTE [U] yield sets; SAscore/SCScore/**RAscore**/SYBA (proxy scores — no experimental synthesizability gold) [C].

**PK / PBPK / DMPK:** **TDC PK** (clearance/half-life/VDss/PPBR regression) [C]; **DMPKBench** (PK *reasoning*, >100k QA) [C]; **PBPK ML benchmark — NONE** (OSP/PK-Sim mechanistic; GastroPlus commercial) [confirmed gap]; allometric scaling — only compilations (Lombardo 1,352) [U].

**Clinical trials — datasets AND agents:** **TrialBench** ⭐ (23 datasets, 8 tasks incl. dose-finding + AE) [C]; **HINT + TOP** (trial-outcome) [C]; **CTOD/CTO** (~125k auto-labeled) [C]; **TrialGPT** (patient-trial matching, Nat Commun 2024) [C]; **TREC Clinical Trials** [C]; **Chia** (1,000 trials, 12,409 criteria) [C]; **n2c2 2018** cohort-selection + ADE [C/U]; **PyTrial** (meta-suite) [C]; **AutoTrial** (criteria design) [C]; DeepEnroll/COMPOSE/Trial2Vec [U]. Pharmacovigilance: FAERS / ADE-corpus / n2c2 — no canonical ML leaderboard [gap].

**Dose finding:** BOIN/CRM/mTPI = **methods** (simulation OC), not datasets [U]; **TrialBench dose-finding** = the only dataset-form task [C].

---

## 2. Cross-cutting findings (the synthesis that matters)

1. **Leakage control is the state of the art (2024–2025).** LP-PDBBind, CleanSplit/GEMS, PLINDER/PINDER, Runs-N-Poses, DockGen, BayesBind, TDC DTI-DG (temporal), ProteinGym CV-folds, DrugBAN cold/cross splits — plus explicit bias critiques of DUD-E and LIT-PCBA. **Every structure/affinity/VS task in the new series must ship leakage-aware (similarity/temporal-stratified) splits by design, or reviewers will reject it.**
2. **Metric integrity / reward-hacking.** "Beyond Affinity" shows Vina-as-reward is gameable; GenBench3D shows only 0–11% of generated molecules are 3D-valid. **Do not build affinity-only or single-metric success criteria; require physical validity + multi-objective + anti-gaming controls.**
3. **Co-folding models memorize.** AF3/Boltz/Chai accuracy drops sharply on novel ligands/pockets; physics docking wins there. Any structure/co-folding task must stratify by training-similarity.
4. **TDC/TDC-2 is the dominant drug-dev ML hub** and the primary thing to benchmark ADMET/DTI/PK against (and to reuse as gold).
5. **A rich agent-benchmark ecosystem already exists** (Biomni, TxAgent, TxGemma, BixBench, DMPKBench, TxBench-PP, DrugAgent, ChemToolAgent). BioMate's series is *not first* at "drug-dev agent eval" — its differentiation is **execution-grounding against real run artifacts + cross-stage linkage + the confirmed single-stage gaps.**
6. **Early-stage/knowledge/search are well covered** externally — include them as tracks and compete, don't claim white space there.

---

## 3. Where BioMate sits (internal B1–B5) + honest baselines

Implemented suite (scorers `evaluation/scorers/`, adapters `evaluation/adapters/`, gold `evaluation/datasets/`, blueprint `docs/20260427_DRUG_DEV_BENCHMARK_PLAN.md`), 6 execution layers L1 intent→L6 output:

| BioMate | Stage | External analog | Status |
|---|---|---|---|
| B1 ADMET (20) | S2 | TDC ADMET, ADMET-AI, ADMETlab, PharmaBench | internal, ready to export |
| B2 Docking (15) | S1 | PDBbind/CASF/PoseBusters/PLINDER | **public in RealBio** |
| B3 PBPK (15) | S4 | **none (no external PBPK ML benchmark)** | **public in RealBio** |
| B4 BOIN (20) | S5/6 | TrialBench dose-finding (BOIN=method) | **public in RealBio** |
| B5 Target-structure (10) | S0 | CASP/CAMEO/PLINDER; also Open Targets/PrimeKG for target-ID | internal; L6 scorer unconfirmed |

Honest baselines (RealBio `leaderboard.md`): LLMs good at ligand ranking (~0.69), **near-useless at PBPK** (~0.075), mediocre at BOIN (~0.27); BioMate PBPK same-item 0.20 **ties, does not lead**; IND ADMET-AI concordance (n=39) hERG 0.615 / DILI 0.487 / Ames 0.795. Report unedited.

---

## 4. Confirmed white space (what the series should OWN)

Only these are genuinely unoccupied or method-only externally:
1. **End-to-end execution-grounded pipeline** — grade a full run vs real terminal + S3 artifacts (BioMate `execution_grader`). *Flagship.*
2. **Cross-stage causally-linked reasoning** (hERG → reformulate → re-screen → re-estimate PK). Every external benchmark is stage-siloed.
3. **PBPK model prediction (ML)** — no external benchmark.
4. **Dose escalation from real data** — only TrialBench's single task; the field is simulation-method comparison.
5. **Formulation / stability / CMC** — uncovered.
6. **FTO / IP novelty** — no technical benchmark.
7. **ABFE** — no canonical benchmark.
8. **Antibody affinity + developability (unified, leakage-controlled)** — fragmented.

Everything else (ADMET, docking, VS, RBFE, SBDD, QSAR, generation, retrosynthesis, target-ID, perturbation, knowledge, search) has strong external baselines — BioMate competes and cites, does not claim to own.

---

## 5. Revised series design — four tracks (not just tool workflows)

`evaluation/datasets/drugdev_export/` (scaffold committed) is organized into tracks so the non-workflow dimensions are first-class:

- **Track 1 — Molecular / tool-workflow benchmarks** (compete + cite external): B1 ADMET (vs TDC/ADMET-AI), B2 docking (vs PoseBusters/PLINDER — **leakage-split required**), N1 RBFE (vs OpenFE/JACS/Merck), N2 QSAR (vs MoleculeACE activity-cliffs), N3 generation (vs GuacaMol/PMO; **GenBench3D validity + anti-reward-hacking**), N4 retrosynthesis (vs PaRoutes/Syntheseus).
- **Track 2 — Early-stage / target & perturbation** (compete + cite): target-ID/druggability (vs Open Targets/PrimeKG/TxGNN), perturbation response (vs GEARS/PerturBench/Virtual Cell Challenge), experiment design (vs BioDiscoveryAgent/CRISPR-GPT). B5 target-structure sits here.
- **Track 3 — Search / retrieval & knowledge** (compete + cite): literature/evidence retrieval (vs PaperQA2/STaRK-PRIME/LitQA2), drug/chem knowledge (vs ChemBench/MoleculeQA/SMolInstruct), KG reasoning (vs BioKGBench).
- **Track 4 — Execution-grounded & cross-stage** (**OWN — the differentiator**): B3 PBPK, B4 dose, + N5 stability, N6 novelty/FTO, N7 IND-narrative, **N8 end-to-end pipeline execution** (flagship), **N9 cross-stage chain**, and the confirmed-gap singles (ABFE, antibody dev).

**Design requirements baked into every task:** (a) leakage-aware splits (temporal/similarity) for all structure/affinity/VS/target tasks; (b) multi-objective, physical-validity, anti-reward-hacking success metrics; (c) real-data, execution-grounded scoring where BioMate is differentiated; (d) exclude data-boundary tasks (Phase II/III outcomes, PopPK, survival, RWE).

**Priority build order:** N8 end-to-end (flagship, reuses `execution_grader`) → N9 cross-stage → N1 RBFE (biggest tool gap) → export B1/B5 → N5/N6/N7.

---

## 6. Manuscript plan

Build on the seed `research_repos/biomate_drug_discovery_paper/`.
- **Position:** first execution-grounded, cross-stage drug-development benchmark, with leakage-aware and reward-hacking-resistant design — explicitly motivated by the 2024–2026 leakage/metric-integrity literature (CleanSplit, PLINDER, Runs-N-Poses, BayesBind, "Beyond Affinity").
- **Comparison set:** reuse the RealBio roster (frontier flagships + the four leading Chinese open families **Qwen/DeepSeek/GLM/Kimi** + BioMate + Biomni), and for each task place models against the relevant external baseline (TDC, PoseBusters, OpenFE, MoleculeACE, GuacaMol, PaRoutes, TrialBench, ChemBench).
- **Honesty (non-negotiable):** report leaderboard numbers unedited; LLMs are strong at ligand ranking/knowledge QA and near-useless at PBPK/dose; BioMate's edge is execution/orchestration/cross-stage, **not** beating specialized predictors (ADMET-AI, FEP+) on their single-task metrics; disambiguate name collisions (three "DrugAgent" papers; TxAgent≠TxGemma).

---

## 7. Caveats / integrity

- Carry per-entry confidence tags ([C]/[C2]/[U]); re-verify [U] counts/licenses before external publication (OGB sizes, USPTO counts, SIDER/Tox21 counts, SAIR split/license, CASP16 ligand counts, GEOM-Drugs-revisited, CAMEO start year). Several 2026-dated arXiv IDs were search-surfaced but not opened — flag before citing.
- Do not over-claim leadership; BioMate's measured drug-dev results are mixed.
- "~215 drug-dev workflows" is unconfirmed; the Batch-validated subset is 24 (IDs 12861–12884).
- Leakage-controlled splits and anti-reward-hacking metrics are mandatory design requirements, not options.

## 8. References (internal)

- Blueprint `docs/20260427_DRUG_DEV_BENCHMARK_PLAN.md`; coverage `docs/20260417_DRUG_DEVELOPMENT_COVERAGE_ANALYSIS.md`.
- Scorers/adapters `evaluation/scorers/{admet,pbpk,boin,docking}_scorer.py`, `evaluation/adapters/*_benchmark_adapter.py`; execution grader `evaluation/local_trial/execution_grader.py`.
- Series scaffold `evaluation/datasets/drugdev_export/` (README + MANIFEST + per-benchmark stubs).
- RealBio template `evaluation/datasets/public_export/`; manuscripts `docs/20260817_REALBIO_BENCHMARK_PAPER_DRAFT.md`, `docs/20260918_ONPREM_DOMAIN_LLM_MANUSCRIPT.md`; seed `research_repos/biomate_drug_discovery_paper/`.
