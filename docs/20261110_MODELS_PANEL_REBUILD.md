# 2026-11-10 — Models panel rebuild (Track A)

Branch `track/a-models` · PR into `integration/unmerged-20261110` · **not deployed, not synced**.

## Why

The founder's review of the deployed Models panel (commit `2faa9a9a`):

- "the entire model panel is not working at all … all fake placeholders?"
- "why the function is strict to a specific task — molecule generation?"
- "if all molecule shaped, you can put them all into a tab of molecule learning. However, as the biomate platform, it is not enough. we need the general ability of ml/dl, too."
- No "在聊天中检查" (check in chat) punts; the target column must be a dropdown of real columns; no English in the zh UI; no placeholder tabs.

What we found when we audited it:

| Problem | Root cause |
|---|---|
| Nothing in the panel trained anything | `model-setup.tsx` / `spec-setup.tsx` only built a `/?draft=` chat message. The chat path then re-extracted the config from prose (lossy), and on dev it is gated by `ML_TRAINING_ROUTING`, which is unset, so panel-initiated training never happened. There was no API that started training from structured fields. |
| Target column was free text | The form never read the dataset. |
| General (non-molecular) data could not train | `datasets._load_csv` required a SMILES column; the tabular loader was CSV-only. `ludwig_tabular` was molecular-only, despite being labelled "deep learning". |
| Every `s3://` dataset failed at runtime | `_load_s3` raised `NotImplementedError`, and the LLM/DPO/GRPO loaders did too. The scRNA and protein diffusion trainers passed the raw `s3://` string to file readers. They were all written assuming "the executor stages s3 inputs", but every `ml_training` `.nf` passes `params.dataset` as a plain value, so nothing stages it. |
| Gate on `macro_f1` was evaluated backwards | `macro_f1` was missing from `_HIGHER_IS_BETTER_METRICS`. |
| The "deep learning & foundation models" tab | It searched Nextflow pipelines (`/api/workflows/search`, hard-coded query), not models, and every hit opened in chat. |
| House style tab | Its only data source is `regulatory_pair_recorder` (the IND editor), which is hidden, so the tab could only show its empty state. |
| The library said nothing about broken models | A model whose inference failed (for example openfold2 on the NVIDIA side) looked the same as a working one. |

## What changed

### How training is launched now

```
Panel (训练 / 分子学习)
  ├─ GET  /api/projects/:id/files                 → project files
  ├─ POST /api/perception/profile {datasetRef}    → real columns + sample rows
  ├─ POST /api/model-training/plan  (Node, new)
  │     auth + project access (owner/member), file resolved from the DB (never
  │     from the client), staged to the Batch bucket with the same helper the
  │     execute path uses, whitelisted fields forwarded with the admin key
  │     └─ POST /api/model-training/plan (Galaxy, new, require_admin, X-BioMate-User-Id)
  │           ml_training/plan.py: structured fields → TrainingConfig.validate()
  │           → nextflow_path_for(model_type) → to_workflow_ga()
  │           → compute_config.container = _resolve_container(cfg)
  └─ POST /api/workflows/execute {workflowDefinition, executionConfig:{mode:'production',
        executionEngine:'nextflow', computeConfig}, projectId}
        → an ordinary run: run record, SSE, billing, Run Manager, and it appears in
          GET /api/model-tracks/train. The panel shows it inline and polls
          /api/workflows/runs/:id/status. "在运行管理器中查看" opens the chat page's
          Run Manager on the all-chats scope (via its persisted localStorage
          state); the Run Manager has no per-run deep link (`?run=` is not read
          anywhere), so we do not pretend to focus the run.
```

There is no chat draft anywhere in the Models module. `ML_TRAINING_ROUTING` is not involved.

The container is chosen by the plan and passed through `executionConfig.computeConfig.container`. The executor's own path-based fallback only distinguishes the TRL image from the CPU image, so it would put scRNA or protein diffusion into the wrong image.

### Tabs (exactly three)

- **训练 Train.** General ML/DL:
  - scikit-learn tabular classification/regression (stratified 5-fold CV)
  - **Ludwig tabular neural net on generic features** (new: `featurizer='none'`)
  - LLM fine-tuning (Ludwig LoRA/QLoRA, TRL DPO, TRL GRPO)
  - scRNA diffusion (scDiffusion)
  - protein backbone diffusion (RFdiffusion)

  Below the launcher is the training-runs list, with a Run Manager link per run.
- **模型库 Model library.** The registry and "run a model" are merged. The catalog table annotates each model with the owner's last inference result. A failed one shows the real backend reason (`lastInference.error`), along with the owned registered artifacts and inference.
- **分子学习 Molecular learning.** RDKit-descriptor models over a SMILES column (gradient-boosting baseline, and a Ludwig network with `featurizer=rdkit_2d`), plus the DMTA rounds.
- **Hidden:** House style (`HOUSE_STYLE_HIDDEN`; the hooks are kept so it can be re-enabled together with the IND editor).
- **Removed:** the workflow-search "pre-built foundation models" section and the DL/FM tab.

### Launcher behaviour

- **Target column** is a dropdown of the dataset's real columns from `/api/perception/profile`.
- **Task type** is suggested from that column's values and stays editable. Non-numeric values, or few distinct integers, suggest classification. Fractional values suggest regression.
- **Model name** is filled in automatically (`<file stem>-<target>`, language-neutral) and stays editable.
- **Model types are filtered by the dataset:**
  - table → tabular learners plus LLM SFT. DPO is offered only when the table has `prompt/chosen/rejected`, and GRPO only when it has `prompt`.
  - `.h5ad` → scRNA diffusion.
  - `.pdb`/`.cif` → protein diffusion.
  - Molecular types appear only when a SMILES column is detected, either by name or by values with real structure. IDs like `c1`/`S1`/`TP53` are rejected.
- **Metrics** are limited to those the trainer actually reports. This mirrors the `plan.py` table, so a gate can never fail closed on a metric that is never produced. The gate label reads "minimum" or, for MAE, "maximum".
- **Not offered, with the reason returned by the plan:**
  - `chemprop_gnn` — no training loop exists.
  - `tabular_diffusion` — no Nextflow wrapper forwards its `tab_*` parameters.
  - GRPO's `composite` reward — it needs a `reward_spec`, which has no form yet.

### General data loading (`ml_training/datasets.py`)

- `read_table_rows()` is one reader for CSV / TSV / `.tab` / `.txt` / JSONL / NDJSON / parquet (and `.gz` for the text formats). The molecular, tabular, LLM and preference loaders all use it.
- SMILES is required only for molecular model types (`sklearn_gbr`, `chemprop_gnn`, and `ludwig_tabular` with `rdkit_2d`). `TrainingConfig.validate()` now rejects `featurizer='none'` for those types, and rejects scaffold/k-fold splits for generic Ludwig.
- `resolve_local_dataset_path()` stages `s3://` in one place. It is used by the molecular, LLM, DPO, GRPO, scRNA and protein loaders.

### i18n

- 171 `models.*` keys, complete in both `en` and `zh`. The keys only the deleted chat-draft forms used were removed.
- The panel, launcher, runs list, library, run-a-model and rounds have no hard-coded UI strings left.
- Backend error text is shown inside a localized sentence ("该配置未被接受…：{detail}"). It is data, not UI chrome.

## Files

**Backend**

- `backend/lib/galaxy/ai/ml_training/plan.py` (new)
- `backend/lib/galaxy/webapps/galaxy/api/model_training_plan.py` (new)
- `ml_training/{datasets,config,routing,training_job,ludwig_adapter,ludwig_trainer,scrna_diffusion_trainer,diffusion_trainer}.py`
- `webapps/galaxy/api/models_inference.py` (last-inference record per owner and model)
- Tests: `ml_training/tests/test_general_tables_and_plan.py`, `test_plan_router.py`, and an update to `test_datasets.py`

**Node**

- `frontend/server/model-training-plan.ts` (+ `.test.ts`)
- `routes.ts` (route wiring)
- `model-surface-access.ts` (admin bridge allows exactly `/api/model-training/plan`)
- `model-training-activity.ts` (falls back to the project file name for the dataset label)

**Client**

- `components/models/`
  - rewritten: `models-panel.tsx`
  - new: `training-launcher.tsx`, `training-logic.ts`, `training-specs.ts`, `models-i18n.test.tsx`, `training-launcher.test.tsx`
  - changed: `run-pretrained.tsx` (localized), `models-api.ts`, `types.ts`, `index.ts`, `models.test.tsx`
  - deleted: `model-case.tsx`, `model-setup.tsx`, `spec-setup.tsx`, `deep-learning-models.tsx`, and their tests. `model-case` was imported only by `index.ts`.
- `locales/{en,zh}/common.json`

## Tests (local)

- `npx tsc --noEmit -p .` → clean.
- `npx vitest run` → 2650 passed, 43 skipped, 3 failed in 2 files: `server/doc-code-drift.test.ts` and `server/adhoc-analysis-routing.test.ts`. Both read files that this worktree's sparse checkout excludes (for example `evaluation/routing_eval/runs/…` → ENOENT). Neither file, nor anything they read, was changed here.
- Models module: 54 tests across 6 files, all passing. They include:
  - a **bilingual render test** with a positive control: injecting a hard-coded "Training runs" fails the zh run;
  - launcher tests for the plan→execute flow and error surfaces.
- `npx vitest run server/model-training-plan.test.ts server/model-surface-access.test.ts server/model-training-activity.test.ts` → 22 passed.
- `python3.9 -m py_compile` passes on every changed `.py`.
- `PYTHONPATH=lib python3.9 -m pytest --import-mode=importlib lib/galaxy/ai/ml_training/tests` (with `test_real_sklearn_e2e.py` ignored) → 300 passed, 2 skipped, 4 failed. Before this change the same run gave 278 passed and the same 4 failures, all `TypeError` inside the local scipy/numpy build (`scipy.interpolate` import / "Cannot convert numpy.ndarray"). `test_real_sklearn_e2e.py` fails at collection for the same scipy reason.
- `import galaxy.webapps.galaxy.api.model_training_plan` cannot be tested locally: the Galaxy app import needs `beaker`, which this machine lacks, and the same is true of the existing `models_inference`. `test_plan_router.py` therefore loads the router by file path against a Galaxy-compatible `Router` stand-in, and checks the route, `require_admin=True`, 403 without an owner, and 400 with the validation message.

Live read-only checks on dev (code not deployed) confirmed the contracts this relies on:

- `GET /api/projects/:id/files` returns `{files:[{id,name,s3_key,…}]}`.
- `POST /api/perception/profile` returns `columns` + `sampleRows` for CSV and JSONL.
- `GET /api/models` returns the catalog shape.
- `GET /api/model-tracks/train` returns `{runs:[…]}`.
- `POST /api/model-training/plan` returns 404 today, as expected because the route is not deployed.

## Must be verified live after deploy

1. **Rebuild the ml-training image** (`.github/workflows/ml-training-image.yml`). The loader changes (JSONL/TSV/parquet, s3 staging, generic Ludwig) run inside `biomate/ml-training:latest`, which was last built on Nov 5. Until it is rebuilt, a panel run reaches Batch with the old loader, and a non-SMILES table would fail exactly as before. The TRL, sc-diffusion and diffusion images also carry `ml_training`, so they need a rebuild for s3 staging of LLM, h5ad and PDB inputs.
2. **A real Batch run from the panel**, for example a JSONL expression table → `sklearn_tabular`, classification, with a gate. Check that:
   - the run record appears in the Run Manager and in the 训练 runs list;
   - status moves through queued → running → completed;
   - `metrics.json` reports the gate metric;
   - "登记训练结果" registers a version.
   Repeat once with `ludwig_tabular` (generic) and once with `sklearn_gbr` on a SMILES table.
3. **Staging:** confirm `_stageProjectFileToNextflow` copies `S3_BUCKET_NAME/<s3_key>` into `NEXTFLOW_S3_BUCKET/uploads/project-<id>/<name>`, and that the Batch role can read it. This is the same path as the existing execute-time project-file staging.
4. **Parquet:** `/api/perception/profile` does not read parquet, so the target dropdown is empty for a parquet file and the panel shows "无法读取该数据集的列". The trainer itself reads parquet. Fixing this needs parquet support in `data_perception.py`, which belongs to the data-panel track.
5. **Library failure reasons:** after one failed openfold2 inference, `GET /api/models` should carry `lastInference.error` with the NVIDIA-side reason, and 模型库 should show it under the row.
6. **Run Manager:** "在运行管理器中查看" should open chat with the Run Manager showing all chats, with the panel-launched run in the list. A per-run focus link needs the chat page to read a run id from the URL (chat-UI track).

## Known gaps / next

- The GRPO composite reward needs a `reward_spec` editor.
- `tabular_diffusion` needs a Nextflow wrapper that forwards `tab_*` parameters before it can be offered.
- `chemprop_gnn` has no training loop.
- The DMTA rounds section is read-only. Starting a loop from the panel is not built.
- The Run Manager has no per-run deep link (chat-UI track).
