# DrugDev-Bench: an execution-grounded, cross-stage drug-development benchmark for AI agents

**Review-ready draft v1 (2026-10-27).** The third of three benchmark manuscripts (siblings: RealBio =
bioinformatics workflow automation; routing-search = resource/channel routing). DrugDev-Bench covers the
**drug-development pipeline** (target ID → hit discovery → hit-to-lead → lead optimization → preclinical →
Phase I). Design, landscape survey, and honesty constraints: `docs/20261021_DRUGDEV_BENCHMARK_LANDSCAPE_AND_SERIES.md`,
`evaluation/datasets/drugdev_export/README.md`. Numbers trace to `drugdev_export/leaderboard.csv` and the
committed task data; unmeasured items are marked `[TO BE MEASURED]` (never invented).

**Status:** draft; NOT submit-ready — open items in §7 gate submission.

## Abstract
The external drug-development benchmark landscape is almost entirely **single-stage prediction** (TDC/ADMET-AI,
PDBbind/CASF/PoseBusters, OpenFE-FEP, GuacaMol, USPTO) or **siloed QA / analysis agent tasks** (LAB-Bench,
GPQA, BixBench, DMPKBench). **No existing benchmark grades an execution-grounded, cross-stage drug-development
pipeline against real run artifacts**, and PBPK and graded dose-escalation decisions have **no external ML
benchmark at all**. DrugDev-Bench targets this white space. We report baselines unedited: frontier LLMs are
strong at ligand ranking but **near-useless at PBPK and weak at dose-finding** on these tasks — with an
important caveat we surface in §5 (the original PBPK prompt was endpoint-underspecified; fixing the spec
roughly triples the score). We do not claim a platform capability win on single-task prediction; the thesis is
that the frontier is leakage-control, metric integrity, and the uncovered execution-grounded cross-stage
tasks.

## 1. Introduction — the white space
Three things the deeper survey establishes (`...LANDSCAPE_AND_SERIES.md` §0): (1) target-discovery,
perturbation, search, and knowledge tasks are *well* benchmarked externally (BioDiscoveryAgent, GEARS, Arc
Virtual Cell Challenge, Open Targets, PaperQA2, ChemBench) — we **compete + cite**, we do not claim to own
them; (2) the real methodological frontier is **leakage control + metric integrity** (LP-PDBBind,
CleanSplit/GEMS, PLINDER/PINDER, Runs-N-Poses; the "Beyond Affinity" finding that Vina-as-reward is gameable)
— any benchmark without leakage-aware splits and reward-hacking-resistant metrics is obsolete on arrival;
(3) the genuine BioMate white space is narrower and sharper: **execution-grounded end-to-end and cross-stage
pipelines** (no external benchmark grades these) plus confirmed single-stage gaps (PBPK-ML, dose-from-real-data,
formulation/stability/CMC, FTO/IP, ABFE).

## 2. Related work (compete + cite)
Agentic drug-discovery (Biomni, TxAgent+ToolUniverse, TxGemma/Agentic-Tx, DMPKBench, TxBench-PP, ChemCrow);
structure/affinity with leakage-aware splits (PDBbind/LP-PDBBind, PoseBusters, PLINDER, OpenFE-FEP, DockGen,
BayesBind); property/ADMET/tox (TDC/ADMET-AI); generation (GuacaMol/PMO + GenBench3D validity); synthesis
(USPTO/PaRoutes). DrugDev-Bench positions **against** these on the single-stage tracks and **owns** the
execution-grounded cross-stage track. (Full survey: `...LANDSCAPE_AND_SERIES.md` §1, with [C]/[C2]/[U]
confidence tags carried through.)

## 3. The benchmark — four tracks
Organised as four tracks (not only tool/execution workflows):
- **Track 1 — molecular / tool-workflow** (compete+cite): `admet_benchmark` (n=20), `docking_benchmark`,
  `rbfe_benchmark` (n=8), `qsar_benchmark` (n=2), `retrosynthesis_benchmark` (n=2).
- **Track 2 — early-stage / target & perturbation** (compete+cite): `target_id_benchmark` (n=2),
  `target_structure_benchmark` (n=10), perturbation (vs GEARS/Virtual Cell Challenge).
- **Track 3 — search / retrieval & knowledge** (compete+cite): retrieval (vs PaperQA2/STaRK-PRIME) and
  `process_knowledge` (n=6).
- **Track 4 — execution-grounded & cross-stage (OWN — the white space):** `pbpk_benchmark` (n=15, no external
  PBPK ML benchmark), `boin_benchmark` (n=20, dose-from-data), `dose_*` (projection/schedule/decision),
  `tissue_exposure`, `special_population`, `leadopt_triage`, `workflow_chain`, and the flagship
  `pipeline_e2e_benchmark` / `cross_stage_benchmark` (execution-scored).

**Design requirements (mandatory, carried from the survey):** leakage-aware (temporal/similarity-stratified)
splits for every structure/affinity/VS/target task; anti-reward-hacking, multi-objective, physical-validity
metrics (not affinity-only); execution-grounded scoring where BioMate is differentiated; exclude data-boundary
tasks (Phase II/III outcomes, PopPK, survival, RWE).

## 4. Methods / scoring
One deterministic scorer per task (`evaluation/scorers/{admet,pbpk,boin,docking}_scorer.py`), reusing the
RealBio public-export machinery (`../public_export/score.py`, `run_all.py`). Roster = frontier flagships + the
four leading Chinese open families (Qwen, DeepSeek, GLM, Kimi) + BioMate + Biomni. PBPK: fraction within
2-fold of the published reference; BOIN: MTD-selection accuracy (18 scorable items; null-true-MTD items
excluded); drug-discovery: mean Spearman rank of predicted vs reference ligand order.

## 5. Results (the three adequately-powered tasks; `drugdev_export/leaderboard.csv`)
| model | pbpk_2fold (n=15) | boin_mtd (n=20) | dd_spearman (n=15) |
|---|---|---|---|
| Claude Opus 5 | 0.133 | 0.444 | 0.70 |
| GPT-5.6 | 0.200 | 0.500 | 0.70 |
| Gemini 3.1 Pro | 0.000 | 0.278 | 0.70 |
| GPT-5.6-luna | 0.200 | 0.389 | 0.70 |
| DeepSeek V4-pro | 0.067 | 0.167 | 0.667 |
| Kimi K3 | 0.000 | 0.167 | 0.70 |
| GLM-5.2 | 0.000 | 0.111 | 0.70 |
| Qwen3.8-Max | 0.000 | 0.111 | 0.70 |
| **BioMate 9B (base)** | 0.067 | **0.778** | 0.70 |
| BioMate 9B (SFT) | 0.000 | 0.778 | 0.70 |
| Biomni (A1 scaffold) | 0.000 | 0.500 | 1.0 (n=4 partial) |

**Honest reading (unedited baselines, per the README mandate):**
- **BOIN (dose-from-data):** BioMate 9B base = **0.778, the best of the small/open models** (frontier
  0.11–0.50). This is a genuine small-model strength on a dose-escalation decision task.
- **dd_spearman** clusters at 0.70 across almost all systems — this uniformity warrants a leakage/ordering
  check before interpreting it as pharmacological knowledge (`[TO BE INVESTIGATED]`; Biomni's 1.0 is n=4
  partial, not comparable).
- **PBPK — the construct-validity correction (committee + `docs/20261026_TASK_SPEC_FIXES.md`):** the published
  ~0.0–0.2 scores came from an **endpoint-underspecified prompt** (the item has four reference values —
  Cmax/AUC/t½/Tmax — but the prompt never said which to predict, and the scorer matched Cmax by accident).
  With an explicit-Cmax prompt, PBPK rose to **0.40–0.47** for capable models (4-model partial rerun: Opus
  0.467, Gemini 0.467, GPT-5.6-luna 0.400, Kimi 0.200). So "near-useless at PBPK" is partly a prompt artifact;
  the full consistent-spec rerun is `[TO BE MEASURED]`. We do **not** claim a BioMate PBPK win (same-item ties
  the best LLM, does not lead).

## 6. Limitations (honest)
- **Only 3 tasks are adequately powered** (pbpk n=15, boin n=20, dd n=15). The remaining ~15 micro-tasks are
  **n=2–10** (fep/qsar/retrosynthesis/target_id n=2; dose_* n=3; …) and are **NOT scored as per-task columns**
  (tiny-data rule) — they are decision-probes that must be **pooled into n≥15 capability categories** (PK/dose,
  med-chem/structure, synthesis) before scoring (`docs/20261024_DRUGDEV_LEADERBOARD_HONEST_SCOPE.md`). admet
  (n=20) and target_structure (n=10) are the next-closest to adequate.
- **No wet-lab ground truth** for any binding/affinity task; structure/affinity scores are modeled.
- **Metal-model / physics caveats** carry over from the αvβ6 FEP work (a separate program) — not claimed here.
- The execution-grounded Track-4 flagship tasks (`pipeline_e2e`, `cross_stage`) are built but **not yet scored
  across the roster** (`[TO BE MEASURED]`).

## 7. Open items before submission (gate)
(1) the full consistent-spec PBPK rerun (all models, explicit-Cmax) + the dd ordering/leakage audit; (2) pool
the micro-tasks into n≥15 capability categories + author more items to clear the adequacy floor; (3) add the
**matched bare-vs-harness** columns (as RealBio/routing-search report) across the roster, empties-aware; (4)
run + score the execution-grounded Track-4 flagship (`pipeline_e2e`/`cross_stage`); (5) finalize
leakage-aware splits for every structure/affinity task. Re-convene the committee before declaring submit-ready
(submit-review gate).
