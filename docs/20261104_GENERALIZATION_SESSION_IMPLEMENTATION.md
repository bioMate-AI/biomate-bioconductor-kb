# Generalization session — implementation log + test assessment (2026-11-04)

Companion to `20261104_PLATFORM_GENERALITY_AUDIT.md` (the map) and
`20261104_DECK_SCENARIO_CAPABILITY_AUDIT_AND_FIXES.md` (the deck scenarios). This is the
detailed record of what was changed, where, how it was tested, what is deployed, and — honestly —
what is NOT yet verified.

## 0. How this session arose
A SYSUCC product deck led to a capability question ("are the illustrated scenarios actually
built?") and then to the deeper one ("are our *good* features general, or case-specific?"). Four
code audits confirmed the pattern: BioMate's **substrate** generalizes, but most of the
**intelligence layers** (routing, params, QC, remediation) are hand-written for ~5–6 sequencing
domains + a drug cluster. This session generalized the top items the SYSUCC + faculty priorities
point to (omics-stratification spearhead), tested at the unit level, and deployed them.

All code below is additive, 3.9-safe, and deployed to dev at commit `001f735e6` (sync healthy,
smoke passed). Activation of the two chat-routing paths is still gated by env flags (ops step).

---

## 1. Model training — generic beyond molecules
**Commits:** `e893c210f` (trainer), `aa72ce523` (routing). **Was:** SMILES-only — `(smiles,label)`
rows, Bemis–Murcko scaffold splits, Chemprop/descriptor trainers. **Now:** also a general
feature-matrix learner with stratified k-fold CV.

Files:
- `backend/lib/galaxy/ai/ml_training/splits.py` — `kfold_split(n, k, seed, labels=None)`:
  deterministic **stratified** k-fold (round-robins each class across folds; plain k-fold without
  labels). `FoldResult`/`KFoldResult` dataclasses.
- `backend/lib/galaxy/ai/ml_training/datasets.py` — `load_tabular_dataset(path, target_col,
  id_cols, task)`: a generic numeric **feature-matrix + label** CSV (e.g. a gene-expression
  matrix), auto-detecting classification vs regression. `LoadedTabularDataset`.
- `backend/lib/galaxy/ai/ml_training/tabular_trainer.py` (new) — `sklearn_tabular` trainer: loads
  its own matrix (mirrors the LLM trainer pattern), runs stratified k-fold CV (mean±std per
  metric), fits a final model, pickles it, writes the standard `metrics.json`; degrades soft if
  sklearn is absent.
- `config.py` — `sklearn_tabular` model type; `split="kfold"` + `cv_folds` (validated).
- `chemprop_trainer.py` / `training_job.py` / `cli.py` — dispatch, placeholder-dataset, `--cv-folds`.
- `routing.py` — a generic-tabular branch: an expression-matrix / subtype request (EN **or 中文**
  表达矩阵/亚型) routes to `sklearn_tabular` + k-fold; molecular aliases still win (no hijack).
- Execution: runs on the existing CPU `nextflow_nfcore/ml_training/chemprop_train.nf` via the
  same CLI; the executor already routes ml_training to the ml-training image.

**Tests (unit):** `tests/test_tabular_trainer.py` (k-fold is a stratified partition, deterministic;
loader reads an expression matrix; trainer runs 5-fold CV end-to-end to >0.8 acc on separable
synthetic data) + 3 routing cases incl. the 中文 亚型 path and the no-hijack guard. **167 pass.**

## 2. Multi-omics routing — all basic layers first-class
**Commit:** `2f6f63ee5`. The engine (`method_selector.py`, `integration_planner.py`) was already
general (arbitrary N layers, 7 methods, data-shape selection) but **dormant behind
`MULTIOMICS_ROUTING` (default off)**, and its text router had two gaps:
- `backend/lib/galaxy/ai/multiomics/routing.py`:
  - added **`spatial`** modality detection (spatial/Visium/MERFISH/Xenium/空间转录组) — the engine
    understood spatial but the parser never picked it up (bad for SYSUCC's NPC atlas).
  - added **中文** aliases across all modalities (表达矩阵/蛋白质组/代谢组/甲基化/单细胞/突变/拷贝数),
    integrate verbs (整合/融合/多组学), and goals (分型/亚型/分层/预后分组/生物标志).
  - `_extract_modalities` now **consumes matched spans** (most-specific first) so "spatial
    transcriptomics" resolves to spatial, not spatial + RNA.
- Proteomics + metabolomics confirmed first-class (correction: they are foundational omics, not
  niche — multi-omics stratification is incomplete without them).

**Tests (unit):** 40 pass (incl. zh spatial+proteomics+metabolomics → correct **SNF** plan; the
no-double-match guard). Verified end-to-end through routing→selector: a zh request
"整合空间转录组、蛋白质组和代谢组数据做患者分型" yields a runnable SNF integration plan.

## 3. Arbiter (Pattern A) — fusion engine reusable beyond target-ID
**Commit:** `b51b3d490`. The fusion math was domain-neutral but reached only through target-ID.
- `backend/lib/galaxy/ai/target_id/arbiter.py` — added `fuse_channels(channels, method, z_thresh,
  weights, top_k)`: a domain-neutral entry point that fuses arbitrary named channels of
  `{entity: score}` into ranked, confidence-tiered entities (genes, papers, cell types,
  candidates, QC signals — anything). Accepts `ChannelResult | (name,scores) | dict`.
- `types.py` — `TargetScore.entity` property (generic alias for `.target`).

**Tests (unit):** `arbiter_test.py` — 5 cases exercising fusion on **non-target entities**
(documents), both methods, mixed input types, top_k, the entity alias. 64 target_id tests pass
(10 pre-existing FastAPI-route import errors are unrelated).

## 4. QC-gate engine (Tier-2) — gates from DATA
**Commit:** `001f735e6`. The general counterpart to the ~45 hardcoded per-process QC branches.
- `backend/lib/galaxy/ai/qc_gate_engine.py` (new) — workflows **declare** gates as data (name,
  metric, op, threshold, severity, evidence); `evaluate_gates(declared, metrics)` classifies each
  **pass / 提醒(advisory) / 中止(halt)** with provenance, generically. `parse_gate_specs` accepts
  the aliases a `qc_metrics.json` self-description uses (operator/limit/action/citation/source) and
  中文 severity. A brand-new domain gets real gates from its declared data alone.

**Tests (unit):** `qc_gate_engine_test.py` — 7 cases (new-domain genericity, pass/advisory/halt,
all operators, alias + dict-form + 中文 severity parsing, missing-metric → not_evaluated-not-crash,
bad-spec validation). **Self-contained; NOT yet wired into `qc_trace_monitor.py`** (that wiring +
a dev run is the follow-up).

---

## 5. Findings (diagnostics, not fixes)
- **Spatial subworkflows are vignette-bound** (`spatialde` takes `Rep11_MOB_0`, `spatialdecon`
  takes `nsclc`) → cannot be chained as-is; a composed pipeline needs **contract standardization
  first** (then compose visiumio/spatialexperiment → QC → spatialde → spotlight), then a dev
  Visium run. No slide-image segmentation (no cellpose/stardist).
- **Catalog scan (reassuring):** only **~10 / 1,837** bioconductor subworkflows are bound to a
  hardcoded example dataset. Vignette-binding is NOT a catalog-wide problem — the generality gaps
  are in the intelligence layer, not the workflows.

## 6. Deploy status
- All of §1–4 are committed, in PR #295, and **deployed to dev at `001f735e6`** (sync healthy,
  gunicorn fresh module load, smoke `PASS workflow=bulk_rnaseq_de_analysis`, db-search OK).
- **ACTIVE in chat (2026-11-04, later same day):** `ML_TRAINING_ROUTING=1` + `MULTIOMICS_ROUTING=1`
  are now set on `biomate-galaxy-dev` via `scripts/enable_generalized_routing_on_dev.sh on` (a
  `docker commit` snapshot recreate — see the runbook doc for why not reimage). **Verified live** with
  `EXPECT_FLAGS_ON=1 scripts/smoke_generalized_routing.sh`: **3 pass / 0 fail / 0 flag-off** — a chat
  request on an expression matrix routes to `sklearn_tabular`, and a zh 整合空间转录组+蛋白质组+代谢组
  request routes to the SNF multi-omics integration plan. Revert with the script's `off`.
- **QC-gate engine WIRED + live-verified** on dev (`jobs/qc_trace_monitor.py`, commits `a26e61fcd`
  + fix `3a8adcbe5`; deployed in `67fecf42`). Running `test_qc_declared_gates.py` against the live
  handler is **7/7**. The live run caught a real gap the laptop could not (no `pulsar`/`boltons`): a
  passing declared-only gate returned `(None, [])` ("no QC") instead of `(True, [])`; fixed by
  tracking `_declared_evaluated` so a clean declared-gate pass is a real pass while a gate skipped
  for a missing metric still yields no verdict. §4 + §8-item-4 follow-ups closed.

## 7. Test coverage — honest assessment (see §8 of this doc for the plan)
What IS covered: **unit/logic level, thoroughly** — splits, loaders, trainers, routing parsers,
fusion, gate evaluation (218 passing across the four modules). What is **NOT** covered:
- **No end-to-end execution.** We have not run, on dev, a generic tabular training job to completion
  on a real expression matrix, nor a multi-omics SNF integration, nor the QC gate engine inside a
  live run. The code routes/evaluates correctly in unit tests; whether these paths *execute* on
  Batch at scale is UNVERIFIED.
- **The generalizations are deployed but dormant** (flags off) → zero real-traffic exercise.
- **`fuse_channels` has no real 2nd consumer** — it is tested on synthetic entities, which proves
  the API, but the audit's point ("generality unexercised") is only half-closed until a real task
  (e.g. literature or multi-omics evidence fusion) uses it.
- **The QC-gate engine is not wired in** → never exercised in a real QC flow.

## 8. Should we test more? — recommended plan
Yes, and the high-value tests are **integration / execution on dev**, not more unit tests:
1. **Activate + CPU-Batch smoke (model training):** set `ML_TRAINING_ROUTING=1`, send a chat
   request on a small real expression matrix ("train a subtype model on this matrix, 5-fold CV"),
   confirm it routes → `sklearn_tabular` → runs on Batch → returns CV metrics + a registered model.
2. **Activate + integration smoke (multi-omics):** set `MULTIOMICS_ROUTING=1`, send a 2–3 layer
   zh request, confirm the SNF plan **executes** (not just plans) and produces a subtype clustering.
3. **A real 2nd consumer for `fuse_channels`:** wire it into one existing multi-source task (e.g.
   literature/evidence fusion) + an integration test, to truly exercise the general engine.
4. **Wire + test the QC-gate engine** as the fallback for unmatched processes in
   `qc_trace_monitor.py`, with a run that declares gates in `qc_metrics.json` and asserts
   pass/advisory/halt — validating on dev.
5. **A SYSUCC-representative dataset test** (a CRC-subtype expression cohort or an NPC multi-omics
   set) end-to-end — the real proof the generalizations work on hospital-grade data, not fixtures.

The unit coverage makes the logic safe to deploy; items 1–5 are what make it *proven in production*,
and each needs a dev-validated cycle (a CPU Batch run, cheap; no GPU).
