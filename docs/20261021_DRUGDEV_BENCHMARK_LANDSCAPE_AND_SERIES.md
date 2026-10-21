# Drug-Development Benchmark Landscape Survey + BioMate Drug-Dev Benchmark Series Design

**Date:** 2026-10-21
**Status:** survey + design (grounds a new drug-development benchmark series + manuscript, parallel to RealBio)
**Inputs:** a web-verified external survey of existing drug-dev benchmarks; an internal audit of BioMate's drug-dev evals (B1–B5) and workflows; the RealBio packaging template (`evaluation/datasets/public_export/`).

**Bottom line:** BioMate already has an implemented 5-benchmark drug-dev suite (B1–B5, scorers + gold + a blueprint doc), three of which are in the RealBio public leaderboard. The external landscape is almost entirely **single-stage prediction** (Category B) or **QA / siloed-analysis agent tasks** (Category A); **no existing benchmark grades an execution-grounded, cross-stage drug-development pipeline against real run artifacts.** That gap maps exactly onto BioMate's execution engine and is the differentiation the new series should own. The work is mostly: (a) package B1–B5 as a branded series mirroring RealBio, (b) add the genuinely-missing tasks (S3 lead-optimization first), (c) write the manuscript. Honesty constraint: BioMate's edge is execution/orchestration/cross-stage, **not** beating specialized predictors on single-task metrics (the leaderboard shows frontier LLMs are near-useless at PBPK and BioMate's PBPK same-item ties but does not lead).

---

## 1. External landscape — the survey

Every entry traces to a paper / official repo / benchmark site; entries that could not be fully pinned are flagged **UNVERIFIED**.

### 1.1 Category A — agent / agentic-task benchmarks

| Benchmark | What it tests | Format | Scale | Agentic | Year | Source |
|---|---|---|---|---|---|---|
| **Biomni / Biomni-Eval1** | Autonomous biomedical research (plan+retrieve+code, 25 domains) | end-to-end + QA + code | Eval1 433 inst / 10 tasks | yes | 2025 | github.com/snap-stanford/Biomni; biorxiv 2025.05.30.656746 |
| **LAB-Bench** | Practical biology research skills (LitQA2/SeqQA/ProtocolQA/CloningScenarios/DbQA…) | MCQ (some tool-requiring) | >2,400 MCQ, 8 cats | static-probe | 2024 | arxiv 2407.10362; FutureHouse |
| **BixBench** | Open-ended comp-bio data analysis in notebooks | end-to-end agent (Jupyter capsules) | 53 capsules / 296 Q | yes | 2025 | arxiv 2503.00096 |
| **ChemBench** | Chemical knowledge/reasoning vs chemists | QA | 2,788 Q-A | static | 2024/25 (Nat Chem) | arxiv 2404.01475 |
| **ChemCrow** | LLM chemistry agent (13 tools: synthesis/rxn/safety) | agent + tool-use | demo tasks | yes | 2023/24 (NMI) | arxiv 2304.05376 |
| **Coscientist** | Autonomous AI chemist (plans + robotically executes) | agent + real lab | 6 tasks | yes (robotic) | 2023 (Nature) | 10.1038/s41586-023-06792-0 |
| **TxAgent + ToolUniverse** | Therapeutic reasoning (DDI/contraindication/dosing) via 211 tools | agentic tool-use | 3,168 + 456 tasks | yes | 2025 | arxiv 2503.10970 (Zitnik/HMS) |
| **TxGemma / Agentic-Tx** | Therapeutic property prediction + agentic orchestration | static + tool-use | 66 TDC tasks | partial | 2025 | arxiv 2504.06196 (DeepMind) |
| **DrugAgent (coding)** | Autonomous ML-pipeline coding for ADMET | multi-agent code | ADMET (PAMPA) | yes | 2024/25 | arxiv 2411.15692 |
| **DrugAgent (DTI)** | Multi-agent DTI + explainable repurposing | agentic | 900 kinase-inhib pairs | yes | 2024 | arxiv 2408.13378 |
| **BioPlanner** | Protocol planning (NL → pseudocode) | planning | BioProt (100s) | planning | 2023 (EMNLP) | arxiv 2310.10632 |
| **ScienceAgentBench** | Data-driven discovery tasks (code) | code per task | 102 tasks / 44 papers | yes | 2024 (ICLR'25) | arxiv 2410.05080 |
| **DiscoveryWorld** | Full discovery cycle in a simulated world | agentic sim | 24 tasks | yes | 2024 (NeurIPS) | arxiv 2406.06769 |
| **GPQA** | Graduate expert knowledge (chem 214 / bio 105 of 546) | MCQ | 448 main / 198 diamond | static | 2023 | arxiv 2311.12022 |
| **HLE** | Frontier closed-ended expertise (chem/bio ~18%) | exact-match + MCQ | 2,500 Q | static | 2025 | lastexam.ai (accuracy caveat: ~30% chem/bio may be wrong) |
| **MedAgentBench** | Agent actions in a virtual EHR (FHIR) | agentic tool-use | 300 tasks | yes | 2025 | arxiv 2501.14654 |
| **TxBench-PP** (Latch) | Small-molecule preclinical pharmacology reasoning | verifiable agentic endpoints | 100 evals | yes | 2026 | arxiv 2606.19245 |
| **DMPKBench** | DMPK: experimental design, ADMET MPO, PK, translation | multimodal QA + reasoning | >100k Q-A | multi-agent | 2025 (NeurIPS) | neurips 2025/126041 |
| **SMDD-Bench** | Multi-turn small-molecule design (scaffold hop, lead opt…) | agentic, 5 task types | 502 instances | yes | 2025 | **UNVERIFIED** |

**Takeaway:** these are QA (LAB-Bench, GPQA, HLE, ChemBench), siloed analysis (BixBench, ScienceAgentBench), clinical-EHR (MedAgentBench), or demo-scale real-lab (Coscientist, BioPlanner). **None grades a full execution-grounded drug-dev pipeline against real terminal/output artifacts.**

### 1.2 Category B — technical / method benchmarks (by sub-area)

- **ADMET / property (aggregators):** TDC ADMET Group (22 datasets / 5 groups; TDC overall 66/22), TDC-2 (multimodal), ADMET-AI (Chemprop method, tops TDC), MoleculeNet (17 datasets), Polaris Hub (community platform), OGB `ogbg-mol*`. — tdcommons.ai, moleculenet.org, polarishub.io
- **Docking / pose / VS:** PDBbind (~19,443 complexes; affinity), CASF-2016 (285/57; scoring powers), DUD-E (102 targets; VS, decoy-bias), LIT-PCBA (15 targets; unbiased VS), **PoseBusters** (V1 428 / V2 308; RMSD≤2Å **AND** PB-valid), DockGen (pocket generalization), **PLINDER** (449,383 systems; leakage-controlled), CrossDocked2020 (SBDD training), PoseBench (harness). — key: pose validity + leakage control now first-class.
- **Free-energy (RBFE/FEP):** JACS-FEP / "FEP+" (8 targets, ~200 ligands), Merck/Schindler FEP (8 pharma targets, ~264 ligands), **OpenFE public benchmark** (59 systems, 876 ligands, >7,000 calcs). — RMSE/Kendall-τ.
- **De-novo generation:** GuacaMol (25 benchmarks), MOSES (~1.9M mols), CrossDocked+TargetDiff protocol (pocket-conditioned 3D), Tartarus (physics-based inverse design).
- **Retrosynthesis / reaction:** USPTO-50k/-MIT/-full (top-k exact match), ORD (data standard, not scored), PaRoutes + Syntheseus (multi-step route planning).
- **QSAR / activity cliffs:** MoleculeACE (30 ChEMBL targets; RMSE + RMSE_cliff).
- **Structure / co-folding:** CASP16 (added PL pose+affinity), CAMEO (continuous), PoseBusters, PLINDER, **Runs N' Poses** (2,600 complexes; shows AF3/Boltz/Chai **memorize not generalize**).
- **PK / PBPK:** TDC PK datasets (Clearance_AZ, Half_Life_Obach, VDss_Lombardo, PPBR_AZ — empirical-endpoint regression). **No standardized PBPK ML benchmark exists** — the field is mechanistic (Simcyp, GastroPlus, PK-Sim/OSP). *(CONFIRMED GAP.)*
- **Clinical trial / dose:** TrialBench (23 datasets, 8 tasks incl. dose-finding), HINT/TOP (trial-outcome; 9,045 split / ~17,538 full), CTOD/CTO (auto-labeled). **BOIN = a method (simulation OC), not a shared dataset.**
- **Toxicity:** Tox21 (12 assays), ToxCast (617 assays), ClinTox (clinical tox + approval). (All in MoleculeNet.)

---

## 2. Where BioMate already sits (internal B1–B5)

Implemented suite (scorers in `evaluation/scorers/`, adapters in `evaluation/adapters/`, gold in `evaluation/datasets/`, blueprint `docs/20260427_DRUG_DEV_BENCHMARK_PLAN.md`), scored on 6 execution layers L1 intent → L6 output validity:

| BioMate | Stage | Capability | Gold | Nearest external analog |
|---|---|---|---|---|
| **B1 ADMET** | S2 hit-to-lead | SMILES → hERG/DILI/Ames/Ro5 + exec | 20 compounds | TDC ADMET, ADMET-AI, PharmaBench (adapter present) |
| **B2 Docking / DD-E2E** | S1 hit discovery | protein+ligands → affinity rank (Spearman ρ) | 15 PDB systems | PDBbind/CASF/DUD-E/LIT-PCBA/PoseBusters |
| **B3 PBPK** | S4 preclinical | SMILES+dose → Cmax/AUC/t½ (within-2-fold) | 15 compounds | **none — no external PBPK ML benchmark (BioMate is novel here)** |
| **B4 BOIN** | S5/6 Phase I | scenario → MTD + safety | 20 scenarios | TrialBench dose-finding (BOIN itself is method-only) |
| **B5 Target structure** | S0 target ID | FASTA → structure + druggable pocket | 10 targets | CASP/CAMEO/PLINDER/PoseBusters |

Plus TDC-ADMET runners, an IND gold-standard concordance set (n=39), and a regulatory §2.6 narrative eval (`evaluation/results/regulatory_v6/`). B3/B4/B2 are already in the RealBio public leaderboard.

**Honest baseline readings (from `leaderboard.md`):** LLMs used directly are *near-useless at PBPK* (mean 0.075), *mediocre at BOIN* (0.271), *good at ligand ranking* (0.694). BioMate PBPK same-item = 0.20 (ties best LLM, **does not lead**). IND ADMET-AI concordance (n=39): hERG Acc 0.615 / DILI 0.487 / Ames 0.795. These must be reported as-is.

---

## 3. White space → what the BioMate series should own

The survey's gaps map directly onto BioMate's execution engine and cross-stage orchestration. These are the differentiators (each is genuinely unoccupied or method-only externally):

1. **End-to-end execution-grounded pipeline** — no benchmark grades a full run (assay/sequence → workflow selection → execution → QC → interpretation → report) against **real terminal + S3 artifacts**. BioMate's `execution_grader` already does exactly this. *Flagship differentiator.*
2. **Cross-stage causally-linked reasoning** — e.g. hERG liability → reformulate → re-screen → re-estimate PK. Every external benchmark is stage-siloed. Unoccupied.
3. **PBPK** — no external ML benchmark exists (B3 is already novel).
4. **Dose-escalation as a graded decision** — BOIN/CRM/3+3 are evaluated by simulation OC, not a labeled benchmark (B4 is novel).
5. **Regulatory / IND narrative generation** — no benchmark grades IND §2.6.1 nonclinical narratives / CSRs (BioMate has the regulatory §2.6 eval).
6. **FTO / novelty / IP** — no benchmark for freedom-to-operate, patent-landscape reasoning, or novelty vs prior art (BioMate has the novelty/FTO gate).
7. **Closed-loop DMTA** — no reusable benchmark grades iterative design with a verifiable per-cycle improvement signal (BioMate's auto-loop QC).
8. **Formulation / stability / CMC** — entirely uncovered externally.

Design requirement carried from the survey: any structure/co-folding or VS task **must use leakage-controlled, temporal/similarity-stratified splits** (the PLINDER / Runs-N-Poses finding that AF3/Boltz/Chai memorize). Do not ship a naive-split structure benchmark.

---

## 4. Proposed series — "DrugDevBench" (name TBD)

**Package as-is (already built):** B1 ADMET · B2 Docking · B3 PBPK · B4 BOIN · B5 Target-structure.

**Net-new tasks to add** (this answers "what other tasks should we add" — ordered by value × tractability; workflows for all of these already exist per the internal audit, they just lack a benchmark):

| New task | Stage | External baseline to cite/beat | Novelty |
|---|---|---|---|
| **Lead-opt: RBFE/FEP** | S3 | JACS-FEP, Merck-FEP, OpenFE | has external baseline — **highest priority** (biggest workflow-only white space) |
| **Lead-opt: QSAR** | S3 | MoleculeACE (RMSE_cliff) | external baseline |
| **Lead-opt: MM-GBSA / de-novo generation** | S3 | GuacaMol / MOSES | external baseline |
| **Retrosynthesis / synthesizability** | synthesis | USPTO, PaRoutes/Syntheseus | external baseline |
| **Formulation / stability** | CMC | **none** | novel |
| **Novelty / FTO** | IP | **none** | novel |
| **IND / regulatory narrative** | S5/6 | **none** | novel |
| **End-to-end pipeline execution** | cross | **none** | novel — flagship |
| **Cross-stage chain** (hERG→reformulate→re-screen→PK) | cross | **none** | novel |

Data-boundary tasks to **exclude** (cannot benchmark without patient/in-vivo partnerships): Phase II/III outcomes, NCA/PopPK, survival, RWE/PGx. (These are where TrialBench/HINT operate; we are not competitive there and should not claim to be.)

---

## 5. Packaging — mirror RealBio

Reuse the existing adapters/scorers; add the RealBio-style public export layer so the series is comparable and reproducible. Create a `public_export`-style bundle (sibling to RealBio) with, per benchmark: a `README.md` (task / #items / ground-truth field / metric / attribution / CC-BY-4.0), a shared objective `score.py`, a `MANIFEST.json`, a single `run_all.py`, a `results/<model>/<benchmark>.jsonl` store, and `leaderboard.{csv,md}`. The internal L1–L6 execution-scored engine stays internal; the export gives the public/comparable packaging. Model roster = the RealBio roster (frontier flagships + the four Chinese open families **Qwen/DeepSeek/GLM/Kimi** — the other Chinese families are intentionally excluded) + BioMate + Biomni.

## 6. Manuscript plan

Build on the existing seed `research_repos/biomate_drug_discovery_paper/` (currently "Paper 4: Drug-Discovery QC Governance," early).

- **Positioning:** the first **execution-grounded, cross-stage** drug-development agent benchmark — grading real pipeline runs and multi-stage reasoning, where the existing landscape is single-stage prediction or QA. Cite the survey's gap analysis (§3) as the motivation.
- **Honest framing (critical):** frontier LLMs are strong at ligand ranking but near-useless at PBPK and weak at dose-finding; the BioMate platform's advantage is **execution, routing, QC, and cross-stage orchestration**, not raw single-task prediction. Report the leaderboard numbers unedited. Do not claim BioMate beats specialized predictors (ADMET-AI, FEP+) on their own single-task metrics.
- **Comparison tables:** per-stage leaderboard (reuse the RealBio sweep machinery); for each task, place the models against the relevant external baseline (e.g. RBFE vs OpenFE RMSE, QSAR vs MoleculeACE, docking vs PoseBusters validity).
- **Target:** a methods/benchmark venue; keep the QC-governance thesis from the seed as one axis, add the execution-grounded cross-stage benchmark as the primary contribution.

## 7. Caveats / integrity

- Carry the survey's UNVERIFIED flags (SMDD-Bench; ChemCrow journal DOI; several ligand/complex counts; "TDC agentic tasks" is a misnomer — TDC is static).
- Do not over-claim leadership; BioMate's measured drug-dev results are mixed (PBPK ties-not-leads; ADMET concordance modest).
- The "~215 drug-dev workflows" figure is unconfirmed; the firmly Batch-validated subset is 24 (IDs 12861–12884). Use validated counts in the manuscript.
- Structure/co-folding tasks must use leakage-controlled splits by design.

## 8. References (internal)

- Internal drug-dev blueprint: `docs/20260427_DRUG_DEV_BENCHMARK_PLAN.md`; coverage: `docs/20260417_DRUG_DEVELOPMENT_COVERAGE_ANALYSIS.md`.
- Scorers/adapters: `evaluation/scorers/{admet,pbpk,boin,docking}_scorer.py`, `evaluation/adapters/*_benchmark_adapter.py`.
- RealBio template: `evaluation/datasets/public_export/` (README, MANIFEST, score.py, run_all.py, leaderboard, models.yaml).
- RealBio manuscripts: `docs/20260817_REALBIO_BENCHMARK_PAPER_DRAFT.md`, `docs/20260918_ONPREM_DOMAIN_LLM_MANUSCRIPT.md`.
- Manuscript seed: `research_repos/biomate_drug_discovery_paper/`.
