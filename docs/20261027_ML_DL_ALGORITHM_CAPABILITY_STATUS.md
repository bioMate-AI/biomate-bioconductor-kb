# BioMate ML/DL algorithm capability — status & gaps (train · fine-tune · RL · inference)

Date 2026-10-27. Scope: the *literal* ML/DL algorithm execution capability (not drug-specific
predictors in the abstract). Sources: `backend/lib/galaxy/ai/ml_training/` + `drug_discovery/` +
`bionemo_client.py`, the training/leaderboard docs, and the cyclic-peptide/SDL session
(`research/guangzhou_all_atom/cyclic_llm/`). Honest posture: **real but narrow and mostly dormant.**

## CORRECTION (2026-10-27) — a colleague already validated a DL "Models" module my first pass missed
My initial survey covered only `ml_training/` + `drug_discovery/` and concluded "mostly dormant." That
**understated the real, deployed capability.** A separate **Models module** (Galaxy-API tier, the
train / adapt / optimise / **retrain** tracks behind `/api/models` + `/api/model-tracks/*` and the
Models UI) was **end-to-end validated by a colleague** and is now **LIVE on dev**:
- Validation: `feat/dl-upgrade-wave1–3` (code; **already merged into this branch**) + `feat/models-real-tracks`
  (the e2e harness `scripts/e2e_models_tracks.sh`, `docs/20260907_MODELS_MODULE_TEST_PLAN.md`,
  `docs/20260908_MODELS_TRACKS_E2E_SESSION.md`, +7 backend track tests). Reported green: **tsc + FE vitest
  19/19 + BE shape tests 19/19**, with live A1–A7 wiring (registry catalog, train/adapt/optimise tracks,
  retrain→runs-dashboard, toggle persistence).
- The colleague's one blocker (F1) was *deploy state* — wave3 wasn't on the dev-sync branch. **That is now
  resolved**: this branch contains wave3 and my sync (`11dfae22`) deployed it → **`/api/models` and
  `/api/model-tracks/train` return 200 on dev** (verified 2026-10-27).
- Cyclic-training integration (UniMoMo training-integrity, closed-loop, splits, wetlab-KD→pairs tests) is
  also present in the tree (`research/guangzhou_all_atom/tests/`), refined further on
  `codex/cyclic-training-integration` (10 commits not yet merged).

**So the honest two-layer picture:** (1) the **Models tracks** surface (train/adapt/optimise/retrain) is
**real, colleague-validated, and now deployed** — this is the user-facing DL capability; (2) the lower-level
**`ml_training/` platform** (chemprop-GNN, TRL-DPO/GRPO, Ludwig-LLM below) remains the narrower, partly-stub
layer. The matrix below is that lower layer; read it alongside the validated Models module above.

**Outstanding merges for the full validated set:** `feat/models-real-tracks` (5 commits — e2e harness,
retrain-as-first-class-run, worker-tick) — **cherry-picked into this branch 2026-10-27, tsc + py_compile
green.** `codex/cyclic-training-integration` (10 commits) — too far-diverged to cherry-pick cleanly (all
10 conflict; my branch has newer `research/guangzhou_all_atom/` cyclic work); preserve via rebase, not
cherry-pick.

## DL abilities ARE registered + routable in the workflow DB (`galaxy_ai_tools.db`)
A third correction: beyond the ml_training platform (not in the DB) and the Models module, **69
DL/training/model workflows are indexed in the DB and routable via chat workflow search** — e.g.
**REINVENT4 Generative Lead Design** (generative fine-tune+RL), **Predict ADMET Properties (AI)**
(Chemprop DL), **Qsar Rf Model** / **herg_cardiac_safety_qsar** (QSAR train+infer), **Generate Gene
Embeddings With ESM Models** (FM inference), **bambu_custom_model_training** / **classifyr_advanced_
modelling** (custom model training), **Segment Cells With Deep Learning**, **DeepVariant**,
**DeepEMhancer**, **deepmodeloptim/deepmutscan**. So the DL methods that are *workflow-wrapped* are live
and findable; the "unreachable" caveat applies only to the low-code `ml_training/` trainer platform.

## Capability matrix — the lower-level `ml_training/` platform (train / fine-tune / RL / infer)

Legend: ✅ real+proven-in-repo · 🟡 coded but only config/unit-tested (no real run committed) · 🔴 stub.

| Engine | Train | Fine-tune | RL | Inference | Status | Where |
|---|---|---|---|---|---|---|
| **sklearn GBR** (RDKit desc) | ✅ | — | — | ✅ | **REAL+proven** (`test_real_sklearn_e2e.py`) | `ml_training/chemprop_trainer.py:95` |
| **Ludwig tabular NN** (DL) | ✅ | — | — | ✅ | **REAL+proven** (`test_real_ludwig_e2e.py`; hERG AUC 0.80 on Batch) | `ml_training/ludwig_trainer.py:24` |
| **Ludwig LLM** (LoRA/QLoRA SFT) | — | 🟡 | — | 🟡 | coded, **config-tested only — no real run committed** | `ml_training/llm_trainer.py:29` |
| **TRL DPO** (preference FT) | — | 🟡 | — | — | coded; `test_trl.py` **never imports trl/torch** — unproven | `ml_training/trl_trainer.py:86` |
| **TRL GRPO** (RL) | — | — | 🟡 | — | coded; reward = 3 built-ins only (not injectable); unproven | `ml_training/trl_trainer.py:138` |
| **Chemprop GNN** (molecular graph NN) | 🔴 | 🔴 | — | 🔴 | **STUB** — `NotImplementedError`, GPU image unbuilt, `chemprop_train.nf` pinned `process_low` | `chemprop_trainer.py:89-92`, `chemprop_wrapper.py:120` |
| **REINVENT4** generative | — | ✅ (transfer) | ✅ (staged/DAP) | ✅ (sampling, mol2mol) | REAL CLI wrapper, **the only DB-registered/routable training path**; real run Batch-gated (honest-fail tested) | `drug_discovery/reinvent4_trainer.py:167/398`; `reinvent4_finetune_rl/main.nf` |
| **BioNeMo FMs** (~20: AlphaFold2/Boltz-2/ESMFold/RFdiffusion/DiffDock/Evo2/GenMol/MolMIM) | ✗ | ✗ | — | ◐ | **STUB until a NIM/GPU is provisioned** (honest empty shapes) | `bionemo_client.py:334-646` |
| **PPBR / QSAR-RF / ADMET-AI** predictors | ✅ (PPBR/QSAR) | — | — | ✅ | REAL, pretrained | `ppbr_predictor.py`, `herg_cardiac_safety_qsar`, `ind_assembly.py:1183` |
| **Classical docking / FEP / MD** (Vina/Glide, OpenFE RBFE, Amber MM-GBSA, GROMACS) | — | — | — | ✅ | REAL subworkflows | `subworkflows/drug_discovery/*` |
| **Bayesian optimizer** (GP, Matérn-5/2) | ✅ (refit) | — | — | ✅ | REAL (auto-retrain on assays) | `bayesian_optimizer.py`, `auto_retrain.py` |

### Reading of the four axes you named
- **Train from scratch** — proven only for sklearn + Ludwig-tabular NN (CPU); **GNN stub**; **no foundation-model pretraining anywhere** (only `from_pretrained`). No generic "bring-your-own `nn.Module`/HF-Trainer/Lightning" harness.
- **Fine-tune** — **routable+real only for REINVENT4** (generator transfer-learn). Text-LLM LoRA/DPO (Ludwig-LLM, TRL) is **coded but unproven and not reachable**; LoRA/QLoRA only (no full FT). **No structure/sequence FM fine-tuning** (ESM/Boltz/Chemprop can't be fine-tuned on user data). Cyclic session confirms: BoltzGen fine-tune was run, **base beat it on LOTO → abandoned**.
- **RL** — **routable+real only for REINVENT4** staged-learning (DAP vs affinity×SA×hERG×QED, injectable reward). **TRL GRPO is coded-but-unproven**, and `sb3`/stable-baselines3 is **not present**. Cyclic session adds a verifiable-reward (RLVR)/DPO design.
- **Inference** — REAL for sklearn/Ludwig/PPBR/QSAR/ADMET-AI/classical-docking/FEP; **STUB** for all BioNeMo DL until provisioned. Note: the in-process model registry **can't rehydrate python-mode models across restarts** (no durable versioning), and BentoML serving is scaffold-only.

**Reachability caveat (important):** the entire `ml_training` platform is **not in the workflow DB and has no `train_model`/`fine_tune`/`run_inference` tool**, and its chat route is flag-OFF (`ML_TRAINING_ROUTING`) — so today it's reachable only via a direct `/api/nextflow/execute` call or the container CLI. **REINVENT4 is the only training capability actually indexed/routable in chat.**

## Measured / tested status
- **Training platform:** 78 unit/integration tests green; real Ludwig NN (655 hERG mols → test AUC 0.80), SmolLM2 LoRA SFT ran on Batch. BUT MLflow = no-op, BentoML = scaffold only, and **no benchmark measures training/fine-tune quality** (benchmarks test prediction/routing/decision only).
- **Chat reachability:** the whole training platform is **built-but-unreachable** — `ML_TRAINING_ROUTING` default **OFF** (`routing.py:205`); "train a QSAR classifier" currently misroutes to the hERG prediction workflow.
- **DrugDev-Bench leaderboard** (2026-10-24, only 3 tracks powered): BioMate's real edge = **BOIN 0.778** (best small/open); PBPK weak (~0–0.2); **SFT shows no gain over base**.
- **BioNeMo:** "nothing run against a live GPU/NGC" — all FM structure/generation inference is inactive stubs.
- **Cyclic-peptide session:** DL/FT actually run but mostly **NULL/ceilings** — cross-target transfer unsolved (needs ≥3 same-chemistry targets), ~0.42 novel-target affinity ceiling (data-fundamental, not capacity), representation ceiling (needs 3D), within-target LLM selector not SOTA (abundance-null circularity). Value = the honest negatives + the knowledge/rule architecture.

## Knowledge & rules — can a user steer a DL method?
Today, rule-injection into a model is REAL only in two narrow places:
- **Regulatory IND LLM** — `org_rule_compiler.py` mines chosen≻rejected edits into per-org YAML RAG blocks (preferred/banned phrases, citations) injected into the IND LLM prompt; `regulatory_knowledge.yaml` feeds it. Scoped to the IND narrative LLM only.
- **RL reward / QC thresholds** — editable REINVENT4 multi-objective reward + `training_job.py:105` gate thresholds (config-level).

**Gap:** no general mechanism to attach knowledge/rules that steer a drug-dev **DL predictor/generator/docking** run. The **cyclic-peptide session has the gold template to port**: a *provenance-tiered experience KB* (`experience_kb.py`, `medchem_kb.py`) that drives **both tool params AND eval gates from one store** under a **hard-evidence invariant**; **acceptance gates** ("gate before score"); **rule induction** (learns the binder rule from actives/non-actives); **correctness-by-construction generation** (sample only inside the rule space); and the **RLVR reward + held-out-eval-only policy**.

## What's needed next (prioritized)
1. **Make it reachable:** `ML_TRAINING_ROUTING=1` + wire `llm_fill` fallback so training requests stop misrouting.
2. **Implement `chemprop_gnn`** (real chemprop≥2.0 train+infer), build the GPU ECR image, route `chemprop_train.nf` TRAIN to `process_gpu`.
3. **Provision ≥1 BioNeMo backend** (NGC/NIM/GPU) so structure/docking/generation stop stubbing.
4. **Add a molecular/structure FM fine-tuning primitive** (e.g. ESM/Chemprop fine-tune-on-user-assay) — today only text-LLM + REINVENT4 can be fine-tuned.
5. **Close train→track→serve:** real MLflow tracking server + ≥1 deployed BentoML service.
6. **Generalize knowledge/rule injection** beyond the regulatory LLM — port the cyclic-session experience-KB + acceptance-gate + RLVR pattern to steer ADMET/generator/docking.
7. **Benchmark the training capability itself** (train hERG → AUC-vs-target execution benchmark) — nothing currently measures train/fine-tune ability, only prediction.
8. **Reconcile the "~215 drug-dev workflows" claim** — only 24 are Batch-validated.

Key files: `ml_training/{chemprop_trainer,routing,executor_payload,training_job,trl_trainer,llm_trainer}.py`;
`drug_discovery/{reinvent4_trainer,ppbr_predictor,generators,ind_assembly,org_rule_compiler,auto_retrain}.py`;
`bionemo_client.py`; `research/guangzhou_all_atom/cyclic_llm/{experience_kb,medchem_kb,acceptance_gate,rule_induction,reward}.py`;
docs `20261023_ML_DL_CAPABILITY_MAP_FOR_UI_ENRICHMENT.md`, `20260721_ML_TRAINING_PLATFORM_FEATURE_SPEC.md`,
`evaluation/datasets/drugdev_export/leaderboard.csv`.
