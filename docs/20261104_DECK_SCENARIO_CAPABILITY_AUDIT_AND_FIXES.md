# Deck scenario ↔ code capability audit, and the fixes (2026-11-04)

## Why this exists
The SYSUCC product-intro deck (`BioMate 产品介绍（技术版）`) and the BD overview
video embed 10 illustrated product scenarios. Before shipping them to a hospital
client we code-audited each against the real backend (`backend/lib/galaxy/...`),
the connector repo (`/Users/kky/biomate-connector`), and the workflow catalog, to
be sure we are not illustrating capabilities BioMate does not have. Four parallel
audits judged **shipped code only** (not the `*.md` roadmap docs).

The headline framing the audits confirmed: **BioMate's infrastructure generalizes
(execution engine, chat→workflow routing, literature/accession, QC-evidence gates,
run+report), but several "AI does the science" capabilities were still a single
drug-discovery case wearing a general UI.** Model training was the clearest example.

## Scorecard (code-verified)

| # | Scenario (illustration) | Verdict | Note |
|---|---|---|---|
| 1 | 工作方式 chat→workflow | ✅ real | routing + param prefill + 确认并运行 gate + live SSE QC |
| 2 | 文献检索 4-DB cited survey | ✅ real + live | parallel DBs, citation-verification; confabulation bug already fixed; S2 drops out if unkeyed |
| 3 | 运行与报告 | ✅ real | SSE phases + QC halt + output-traceable numbers + auto methods text |
| 4 | 质控依据 QC evidence | ✅ real (strongest) | evidence-graded gates w/ real citations, pass/advisory/halt, surfaced in UI |
| 5 | 公共数据 accession | 🔧 partial | resolve+detect+fetch+run real; "样本信息已读取·分组已标注" shown pre-run is actually read **post-fetch** |
| 6 | 模型训练 | 🔧→✅ **fixed (code)** | was SMILES-only / holdout / routing-off; now generic tabular + k-fold CV + routing |
| 7 | 医院设施 instruments | 🔧 partial | all 5 types have real parsers + real analysis workflows, but connectors only **notify** (no auto-run) and qPCR/ELISA connector map to the **wrong** function |
| 8 | 空间组学 | 🔧 partial | real atomic subworkflows, but **no composed pipeline** and **no slide-image segmentation** |
| 9 | 课题合作 federated | 🔧 partial | real GWAS→eQTL→immune-cell pipeline + on-prem keeps data in-env, but **"联邦式/federated" is the wrong term** (no federated compute) |
| 10 | 研究方案 | 🔧 partial | power-calc + evidence-grading exist, but **no unified cited-protocol generator** |

## What was fixed in this session (committed, locally tested, 3.9-safe)

### 模型训练 — generalized beyond molecules
Commits: `e893c210f` (trainer) + `aa72ce523` (routing). The module was molecule-only
(`(smiles,label)` rows, Bemis–Murcko scaffold splits, Chemprop/descriptor trainers).
Added the GENERAL counterpart so "train a subtype predictor on a gene-expression
matrix with 5-fold CV" is a real capability:
- `ml_training/splits.py` → `kfold_split()`: deterministic **stratified k-fold CV**
  (round-robins each class across folds; plain k-fold without labels).
- `ml_training/datasets.py` → `load_tabular_dataset()`: **generic numeric feature
  matrix + label** CSV (e.g. expression matrix); auto-detects classification vs regression.
- `ml_training/tabular_trainer.py` (new) → `sklearn_tabular` trainer: loads its own
  matrix, runs stratified k-fold CV (mean±std/metric), fits a final model, writes the
  standard `metrics.json`; degrades soft if sklearn absent.
- `config.py`: `sklearn_tabular` model type; `split="kfold"` + `cv_folds` (validated).
- `chemprop_trainer`/`training_job`/`cli`: dispatch, placeholder-dataset, `--cv-folds`
  (mirrors the LLM trainer's load-own-data pattern — no SMILES loader).
- `routing.py`: an expression-matrix / subtype request (English or Chinese 表达矩阵/亚型)
  routes to `sklearn_tabular` + k-fold; molecular aliases still win (no hijack).
- Execution: the existing `nextflow_nfcore/ml_training/chemprop_train.nf` CLI wrapper
  passes `--model-type/--split` through and runs CPU trainers on `process_low`, so
  `sklearn_tabular` runs with no new `.nf`; the executor already routes ml_training to
  the ml-training image (sklearn is present). `cv_folds` defaults to 5.
- Tests: `tests/test_tabular_trainer.py` + 3 routing cases. 167 pass, 2 skipped.

**Activation caveat:** chat routing to any ml_training path is gated by
`ML_TRAINING_ROUTING=1`, an env var set on the host (NOT synced by `sync_to_dev.sh`).
Until that is set on `biomate-galaxy-dev`, a "train a model…" chat message still falls
through to normal workflow search. The code path, trainer, CV and routing logic are
all in place and unit-tested; turning it on for a dev demo is a one-line env change +
a CPU Batch smoke (no GPU).

## Remaining gaps — precise fix plan (NOT shipped blind; need dev validation)

Per the repo's no-speculative-deploy / no-workaround rules, these are documented
rather than half-wired, because each needs a dev/Batch run to verify and I will not
ship unvalidated changes into the live client-facing stack.

1. **医院设施 connector mapping (small, safe once the id is confirmed).**
   `backend/lib/integrations/qpcr_connector.py:211` maps `rt_qpcr_expression →
   "qpcr_differential_expression"` and points at `molecular_biology.pcr_simple` (a
   primer-amplicon *simulation*). The real ΔΔCq workflow is
   `subworkflows/bioconductor/normqpcr/delta_delta_cq_normalization.nf`. Fix: repoint
   `_WORKFLOW_MAP` to the real catalog workflow name (confirm the exact id used by the
   launch path) and do the same for the ELISA→generic-enzyme-kinetics case. Deeper gap:
   connectors only POST a notification (`/api/instruments/new-data` inserts a pending
   row) — nothing auto-runs. Either wire the notification's confirm action to launch the
   mapped workflow, or soften the illustration to "instrument → data → (one click) →
   analysis".
2. **公共数据 pre-confirm sample read (medium).** `/api/accession/resolve` classifies the
   accession and prefills a fetcher, but sample/group labels are only surfaced *after*
   the fetch step runs. To match "样本信息已读取·分组已标注" shown pre-run, extend
   `detect_geo_platform()`/resolve to also pull the GEO SOFT sample table at resolve time
   and return group columns in the proposal. Verify against live GEO.
3. **空间组学 composed pipeline (medium) + slide-image segmentation (large).** Compose
   `visiumio → QC → spatialde → spatialdecon` into a `workflows/bioconductor_spatial/`
   entry (the atomic subworkflows are real). The "import slide image → segment tissue
   regions" step has no backing code (no cellpose/stardist/squidpy) — either add a
   segmentation step or drop that line from the illustration.
4. **研究方案 unified cited-protocol generator (large).** Pieces exist (power-calc Nextflow
   workflows + the `grounded/` evidence-grading engine + the citation-grounded
   ResearchAgent). Compose them into one artifact: evidence-gap → hypothesis → design →
   endpoints → sample-size, each line citation-linked, reusing Scenario-2's citation
   verification. This is a real LLM feature build + eval.
5. **课题合作 "联邦式" (wording).** The capability is real via on-prem (data stays in the
   customer env) + the GWAS→eQTL→immune-cell workflow, but "联邦式/federated" implies
   federated *compute*, which does not exist. Fix the illustration label to
   「本地/院内执行 · 数据不出环境」 rather than claiming federated. (Deck edit + re-capture.)

## Follow-ups
- Set `ML_TRAINING_ROUTING=1` on dev + run a CPU Batch smoke of `sklearn_tabular` on a
  small expression matrix to confirm the end-to-end chat→train path, then the 模型训练
  illustration is fully honest.
- Decide per remaining gap: build vs. reframe-the-illustration. Items 1 and 5 are the
  cheapest honesty wins; 3-slide-image and 4 are real builds.
