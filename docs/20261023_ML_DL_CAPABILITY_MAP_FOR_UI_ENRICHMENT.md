# BioMate ML/DL Capability Map — for UI Enrichment

**Date:** 2026-10-23
**Purpose:** A grounded inventory of BioMate's machine-learning and deep-learning
capabilities, written so the design team can enrich the Models / training UIs to
surface what actually exists. Every claim below is traced to source files and, for
the tool catalog, to SQL queries against the live index. Where a capability is
*built but not wired*, that is stated explicitly — the design must distinguish
**implemented**, **dormant**, and **stub** so the product never promises more than
it does.

This document was prompted by a concrete failure: the `b1-train-custom-model`
tutorial captured the **empty Models landing page** ("this project hasn't trained
a model yet") as its only product screenshot. That page is the wrong surface — a
training run actually renders on the **workflow panel** — and the training route is
**disabled by default**, so a "train me a model" request currently falls through to
ordinary workflow search. The enrichment work below fixes the root cause.

---

## Part A — The integrated DL/ML training platform (`backend/lib/galaxy/ai/ml_training/`)

A low-code, declarative **train → validate → held-out QC gate → register → serve**
loop for molecular / drug-discovery models. It deliberately **reuses** existing
surfaces (workflow run panel, AWS Batch executor, CustomModelRegistry, QC-gate SSE)
rather than fork a parallel stack (`__init__.py:1-26`). All heavy deps are
lazy-imported and guarded, so the orchestration layer runs with none of the ML
stack installed.

### A.1 Open-source foundations

> **These are different *kinds* of tool, not peer options — do not present them as a
> flat menu.** **scikit-learn** is a broad *classical* (non-DL) algorithm library
> (it backs only the GBM baseline). **Ludwig** is a *low-code deep-learning
> framework* that sits a level *above* PyTorch (declarative config → neural net; also
> LLM fine-tunes). **Chemprop** is a single specialized *DL model* (a molecular graph
> neural network), not a framework. So: sklearn = classical ML; Ludwig = DL
> framework; Chemprop = one DL model for molecules. They are complementary backends
> for different jobs (cheap baseline vs. low-code NN vs. molecular GNN), not
> interchangeable equals.

| Capability | Library (OSS) | Where |
|---|---|---|
| Molecular graph NN (message-passing) | **Chemprop** (+ PyTorch) | `chemprop_trainer.py:73` |
| Low-code tabular DL + LLM fine-tune | **Ludwig** (LF AI & Data) | `ludwig_trainer.py:26`, `llm_trainer.py:33` |
| Gradient-boosting baseline | **scikit-learn** | `chemprop_trainer.py:99-102` |
| Molecular featurization (6 × 2D descriptors) | **RDKit** | `ludwig_adapter.py:27-29,118-125` |
| LoRA / QLoRA adapters | **PEFT** | `trl_trainer.py:69-73`, `ludwig_adapter.py:96-99` |
| LLM preference-opt & RL (DPO, GRPO) | **TRL** (HuggingFace) | `trl_trainer.py:88,140` |
| Base LLMs + tokenizers | **transformers / PyTorch** | `trl_trainer.py:60-66` |
| Public datasets | **PyTDC** (Therapeutics Data Commons) | `datasets.py:88-121` |
| Experiment tracking + model registry | **MLflow** | `mlflow_tracker.py` |
| Model serving | **BentoML** (`POST /predict`) | `bento_service.py:52-79` |

Execution images (`executor_payload.py:28-43`): a CPU image
(`biomate/ml-training:latest`, Ludwig+sklearn+RDKit+PyTDC), a separate TRL image
(`biomate/trl-training:latest`, newer torch/transformers that conflict with
Ludwig's pins), and a **not-yet-built** GPU image for Chemprop (`ML_TRAINING_GPU_IMAGE`).

### A.2 Model types — and their maturity (the honesty map)

Canonical `MODEL_TYPES` = six (`config.py:33-34`). **Maturity matters for the UI —
do not present a stub as runnable.**

| Model type | What it is | Library | Compute | Status |
|---|---|---|---|---|
| `ludwig_tabular` | Low-code DL NN over 6 RDKit descriptors — **the default DL model** | Ludwig | CPU | **Implemented** |
| `sklearn_gbr` | Gradient-boosting baseline (the only full local train+infer path) | sklearn | CPU | **Implemented** |
| `ludwig_llm` | Low-code LLM SFT (instruction→response) + LoRA/QLoRA | Ludwig | CPU/GPU | **Implemented** |
| `trl_dpo` | Direct Preference Optimization on {prompt, chosen, rejected} | TRL+PEFT | CPU/GPU | **Implemented** |
| `trl_grpo` | Group Relative Policy Optimization (online RL) with reward fn | TRL+PEFT | CPU/GPU | **Implemented** |
| `chemprop_gnn` | Molecular graph neural net | Chemprop | GPU | **STUB** — train + inference raise `NotImplementedError` (`chemprop_trainer.py:71-92`, `chemprop_wrapper.py:120-126`); GPU image not built |

Real-stack e2e tests exist for the implemented paths
(`tests/test_real_ludwig_e2e.py`, `test_real_sklearn_e2e.py`).

### A.3 Task types (`config.py:26`)

Only three: `classification`, `regression`, `text_generation`. SFT, DPO and GRPO
all map onto `text_generation` (`config.py:177-182`). Primary metric follows task:
classification→AUC, regression→MAE, LLM→loss (`routing.py:114,136`).

### A.4 Datasets (`datasets.py`, `config.DatasetSpec`)

One of three sources (`config.py:71-106`): **named** (`tdc:<name>` public via PyTDC,
or `fixture:herg`), **path** (local CSV with `smiles_col`/`target_col`), or
**s3_uri** (staged to local by the executor — local read raises by design).
10 TDC dataset aliases are recognized by routing (hERG, BBB, AMES, CYP2D6/3A4,
Caco2, Lipophilicity, Solubility, PPBR — `routing.py:49-60`). LLM/RL paths load text
rows (instruction / preference-triple / prompt) from fixtures, HuggingFace
`hf:<name>`, or JSONL/CSV.

### A.5 Lifecycle (`training_job.py:118-182`)

1. Validate config → compute artifact dir.
2. Load data (LLM types load their own text rows).
3. Train **under one MLflow run** (params + metrics + artifacts logged).
4. **Held-out QC gate** (`_evaluate_gate`, `training_job.py:105-115`): compares the
   held-out primary metric to `gate_threshold` (direction from
   `_HIGHER_IS_BETTER_METRICS`). Emits a `qc_gate_results` SSE payload **shaped to
   match the workflow panel's auto-loop UX** (`training_job.py:62-72`).
5. Register the model URI in MLflow.
6. **Register into the per-campaign `CustomModelRegistry` ONLY if the gate passed**
   — a failed-gate model is explicitly *not* made scorable (`training_job.py:163-175`).
7. **Serve** via `BaseModelWrapper` → `POST /api/drug-discovery/{campaign}/models/{name}/run`
   and/or a BentoML `POST /predict` service — no new serving contract.

Execution (`executor_payload.py:60-135`): a `TrainingConfig` becomes a normal
`NextflowExecuteRequest` → `POST /api/nextflow/execute` → **AWS Batch**, with the
same RunStateStore, SSE status, billing and QC-gate/auto-loop as any workflow.
`workflow_domain="ml_training"`.

### A.6 Routing & wiring status — **DORMANT by default**

- `ML_TRAINING_ROUTING` is read via `os.environ.get(...) == "1"` (backend,
  `routing.py:200-207`) and `process.env... === '1'` (frontend,
  `galaxy-assistant.ts:4139`). **Default OFF.** No repo config sets it; docs confirm
  "特性开关 ML_TRAINING_ROUTING 默认关闭"
  (`docs/20260721_ML_TRAINING_PLATFORM_FEATURE_SPEC.md`).
- When OFF, the training hook returns None and the request **falls through to normal
  workflow search** — which is exactly why "train a QSAR classifier" on dev routed to
  the existing *Herg Cardiac Safety Qsar* prediction workflow, not to training.
- `llm_fill` (the LLM gap-filler for free-text requests) is **not wired** into the
  backend call (`ai_assistant.py:4418`), so a request with no recognized dataset
  alias raises → returns None even when the flag is on.

**To make b1 real and demonstrable:** set `ML_TRAINING_ROUTING=1` in **both** the
frontend node process and the Galaxy backend on dev, and wire `llm_fill`. Until
then, the training platform is built-and-tested but not reachable from chat.

### A.7 API endpoints & the two run surfaces (`routes.ts:5006-5061`)

All proxied to Galaxy via one `_dlProxyHandler`:
- `GET /api/models`, `/api/models/:id`, `POST /api/models/:id/infer`
- `GET /api/model-tracks/{train,adapt,optimise}` (+ adapt mutations)
- `GET /api/inference/:runId/result`
- `POST /api/generate`, `GET /api/generate/:runId` (Design & Generate)

**Two distinct run surfaces — critical for design:**
1. **Training runs render on the workflow panel** (`NextflowWorkflowViewer`):
   `TrainingConfig.to_workflow_ga()` emits the standard `workflow_ga` param contract
   (`config.py:14-17,203-289`) — a training job appears as an ordinary workflow card,
   with phases/steps/QC-gate, **no new frontend code**. This is the design-aligned
   surface the demos should show.
2. **The Models page** is a separate read/inference surface (registry + run-a-model).

### A.8 Models page UI current state (`models-panel.tsx`)

Five tracks (`MODELS_TRACKS`, line 41-47):

| Track | Purpose | Wiring |
|---|---|---|
| **Train** | Train on the same compute/gates/tracking as a workflow | Design content + **honest-empty** list (no WS1 read endpoint this wave) |
| **House style** (Adapt) | Inspectable before→after edit pairs; "re-train on my edits" | Mutations wired (`useAdaptToggle`/`useAdaptRetrain`); empty by default |
| **Rounds** (Optimise) | Closed design·make·test·analyse (DMTA) loop; rejected proposals stay visible with reason | Design content + honest-empty |
| **Run a model** | Inference on a fitted model (pick domain → input → infer → poll) | **LIVE-wired** (real infer/poll) |
| **Registry** | Account-level model catalog from `GET /api/models` | **LIVE-wired** |

Honesty contract: no track fabricates data (`models-panel.tsx:12-18`). The Train
"families" card (Language / Tabular AutoML / Diffusion / Molecular property) is a
**narrative grouping**, not a live capability map — note **Diffusion has no backend
trainer**.

---

## Part B — Galaxy's ML toolset (`backend/database/galaxy_ai_tools.db`)

The local index is **not a stub**: **12,312 tools / 4,223 workflows**, 12,299 with
vector embeddings, FTS-indexed. **~338 ML-related tools**; `category='Machine
Learning'` = 80, `category='Statistics'` = 90.

### B.1 The classic Galaxy-ML suite (bgruening, sklearn 1.0.11)

- **Classification:** SVM, k-NN (`sklearn_nn_classifier`), discriminant analysis,
  generalized linear (logistic/ridge/SGD), LightGBM, ensemble (RF/GBM/AdaBoost/bagging).
- **Regression:** generalized linear, stacking ensembles / Super Learner, regression metrics.
- **Clustering / DR:** numeric clustering, PCA, pairwise distances.
- **Model evaluation / validation:** model validation (CV), train/test split,
  train-test-eval, fitted-model eval, classification & regression metrics,
  hyperparameter search (GridSearchCV / nested CV — also handles DL models).
- **Feature selection / preprocessing / pipeline:** feature selection, preprocess/scale,
  pipeline builder, label encoder, to-categorical, synthetic data generator,
  `ml_visualization_ex` (feature-importance / ROC / PR plots).

### B.2 Deep-learning tools (Keras / TensorFlow builders)

- `keras_model_config` → create a DL architecture (sequential layers).
- `keras_model_builder` → add optimizer/loss → classifier/regressor estimator.
- `keras_train_and_eval` → train + evaluate a DL model.
- `keras_batch_models` → batch DL training.
- `model_prediction` → predict with a trained Keras/sklearn model.
- Domain DL tools: DeepMicro (autoencoder), DeepVariant/DeepSomatic, PlasFlow,
  VirHunter, SemiBin, U-Net image segmentation (UnMICST/Coreograph), flexynesis
  (multi-omics DL), etc.

### B.3 Other ML frameworks indexed

Ludwig/PyCaret (goeckslab: `ludwig_train`/`experiment`/`hyperopt`/`visualize`,
`tabular_learner`, `pycaret_predict`, `image_learner`), **TabPFN**, **Cleanlab**
(label-issue detection), **immuneML** (repertoire ML), chopin2 (hyperdimensional),
BiocSklearn, QIIME2 sklearn classifiers.

### B.4 How ML tools are reached

`UnifiedToolSearch` (`backend/lib/galaxy/ai/unified_tool_search.py`): LLM query
analysis → entity match → **vector similarity** (`VectorToolSearch`,
BAAI/bge-small-en-v1.5, 384-dim) → **FTS5** → reciprocal-rank fusion. Reached from
chat via `ai_assistant.py` → intent router / domain specialist →
`galaxy_workflow_generator`.

### B.5 Gap

**No pre-assembled end-to-end ML `.ga` workflow or curated ML `workflow_chain`** in
the local DB (1 workflow references sklearn in `tools_used`; 0 ML chains). ML runs
are assembled on-the-fly by the workflow generator from individual tools. Most
"classifier" workflows present are single-tool Bioconductor ML wrappers (ClassifyR,
scClassify, mixOmics sPLS-DA, etc.), not multi-step sklearn pipelines. (The larger
canonical dev/S3 DB may differ.)

---

## Part C — Implications & recommendations for UI enrichment

### C.1 The end-to-end journey to design (this is what b1 must show)

```
Dataset (upload CSV / pick TDC / pick dataset version)
  → "train a <model> to predict <target>" (chat)
  → Training card on the WORKFLOW PANEL  (pre-run: dataset, model type, task, epochs/lr)
  → Confirm & Run  → phases/steps streaming (AWS Batch), live metrics
  → Held-out QC gate  (pass → offer register; fail → do NOT register, show reason)
  → Finished model: held-out metrics, (for tabular) feature importance, MLflow run id
  → Register  → appears in Registry (account-scoped)  → Run a model (inference)
```

The current `b1` deck screenshot shows **none** of this — it shows the empty Models
landing page. The enriched demo must show the **workflow-panel training run**
end-to-end (the same lifecycle d2-admet shows for a prediction workflow).

### C.2 What to enrich

1. **Train track → a real training-run entry point**, not just a 4-step explainer.
   It should launch the chat→workflow-panel run and then list runs with
   status/gate/metric/version (the list UI exists; it needs a read endpoint + the
   routing flag on).
2. **Training-run card on the workflow panel**: surface model type, task, dataset,
   epochs/lr in pre-run; held-out metrics + feature importance + gate decision in
   after-run. (Reuses `NextflowWorkflowViewer`; mainly content/mapping.)
3. **Rounds (DMTA)** and **House style (Adapt)**: give them read endpoints so they
   show real rounds / learned rules instead of honest-empty.
4. **Model families card**: align it to the six real `MODEL_TYPES` + maturity, or
   clearly mark Diffusion/Chemprop as not-yet-runnable (honesty contract).
5. **Galaxy-ML surface**: there is a large sklearn/Keras toolset reachable via
   search but no dedicated UI. A "classical ML on a table" entry (train/test/CV →
   metrics → feature importance) could expose Galaxy-ML without the DL platform.

### C.3 Honesty & wiring prerequisites (do these before re-capturing demos)

- Turn on `ML_TRAINING_ROUTING=1` (frontend **and** backend) on dev and wire
  `llm_fill`, so "train a model" actually reaches the training platform.
- Keep `chemprop_gnn` marked as not-yet-available (stub) and Diffusion as narrative.
- Preserve the no-fabricated-data contract.

### C.4 Demo-capture quality requirements (ties to the video issue)

When these UIs are re-captured for tutorials:
- Capture/record at **native 2560×1440 or 3840×2160** (viewport at that size, not
  1920×1080 upscaled) — the current 1080p pipeline makes embedded UI text unreadable.
- Show each product screenshot as a **large focal crop** filling the frame/dominant
  panel, cropped to the readable region — no shrunk split-panels, no blank space
  (the b1 whitespace failure).
- Prefer sharper screen-content encoding (`yuv444p` / higher bitrate).

---

## Appendix — primary source references

- Platform: `backend/lib/galaxy/ai/ml_training/{__init__,config,datasets,training_job,
  chemprop_trainer,chemprop_wrapper,ludwig_trainer,ludwig_adapter,llm_trainer,
  trl_trainer,mlflow_tracker,bento_service,executor_payload,routing,cli}.py` (+ `tests/`).
- Routing hook: `backend/lib/galaxy/ai/ai_assistant.py:4409-4440`;
  frontend override: `frontend/server/galaxy-assistant.ts:4130-4146`.
- DL proxy routes: `frontend/server/routes.ts:4999-5061`; client `models-api.ts`.
- Models UI: `frontend/client/src/components/models/models-panel.tsx`,
  `run-pretrained.tsx`, `model-object.tsx`.
- Tool index: `backend/database/galaxy_ai_tools.db` (tables `tools`, `workflows`,
  `workflow_chains`, `tool_knowledge`); search `backend/lib/galaxy/ai/
  unified_tool_search.py`, `vector_search.py`.
- Feature spec: `docs/20260721_ML_TRAINING_PLATFORM_FEATURE_SPEC.md`;
  runbook: `docs/20260717_ML_TRAINING_POC_DEV_RUNBOOK.md`.
