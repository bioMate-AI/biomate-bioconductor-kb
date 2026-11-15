# 2026-11-15 — Cold-start Models module audit + DEV test

**DEV tip (live):** `cb472efe5c13d798b67e02aa642e088e1bdf9847`  
**Fixture:** `lifeifei163361@163.com` (password from `~/.config/biomate/e2e_fixture_password`, not printed)  
**Harness:** API (login once, one project) — Playwright deep suite skipped (local disk / Chrome risk; API pattern matches `design-generate-sm-0`)  
**Evidence:** `/tmp/models_coldstart_harness_20261115T121101Z/`, `/tmp/models_coldstart_session_ds_20261115T122334Z/`

## Catalog (Models module)

Source: `cold-start-dashboard.tsx` → `COLD_MODULES[id=models]` + `cold-start-demo-catalog.ts`.

| Track | Example intent | Bundle | Fixture files | Expected product route |
|-------|----------------|--------|---------------|------------------------|
| Train | Train a potency predictor on our in-house assay data. | `potency` | `bace_assays.csv` | `ml_training` → `chemprop_train.nf` (attached assay) |
| Train | Train an hERG classifier and gate the design loop on it. | `herg` | `herg.csv` | `ml_training` → `chemprop_train.nf` (attached herg.csv) |
| Train | Train a solubility model from our historical plate data. | `solubility` | `solubility.csv` | `ml_training` → `chemprop_train.nf` (attached solubility.csv) |
| Adapt | Adapt the generative model to our chemical series. | `molecules` | `candidate_library.csv`, `1IEP.pdb`, `pilot_reference_actives.smi`, `pilot_target_info.json` | `reinvent4_finetune_rl` |
| Adapt | Fine-tune this property predictor on our measured compounds. | `potency` | `bace_assays.csv` | `ml_training` → `chemprop_train.nf` |
| Optimise | Run the design–make–test loop on this series under a 96-assay budget. | `loop` | `bace_assays.csv`, `candidate_library.csv` | DMTA / Bayesian loop (product gap today) |
| Optimise | Propose the next round and refit on the results. | `loop` | same | same (follow-up turn) |

### Static audit (catalog / assets)

| Check | Result |
|-------|--------|
| Every Models seed in `COLD_DEMO_INTENTS` | Pass |
| Demo assets under `frontend/client/public/demo/cold-start/` | Pass (all non-empty, non-HTML) |
| Raw `s3://` in Models contexts / card seeds | Pass (only a comment mentions s3) |
| `diffusion train` poison in Models contexts | Pass (not present; design biologics/peptides separately guarded) |
| Sharing allowlist | `models:loop` intentionally shares one bundle across both Optimise rows |

Cryo license **402** is out of scope for Models (known blocker on Data analysis / cryo, not this module).

## DEV API results (tip `cb472efe`)

Login once + project `12143210-…` (first harness) / `d44828a1-…` (session_datasets remasure).

| id | Card name | nextflow_path | source | runId | terminal | Verdict |
|----|-----------|---------------|--------|-------|----------|---------|
| models-train-potency | Reinvent4 Finetune Rl | `…/reinvent4_finetune_rl/main.nf` | template_reuse | `91c6c6cc-…` | failed — pydantic `logfile` extra_forbidden | **FAIL** (wrong card) |
| models-train-herg | hERG classifier | `ml_training/chemprop_train.nf` | ml_training | `039bde55-…` | failed — TDC HTML error (`tdcommons.ai`) | Route OK / exec **FAIL** (used `tdc:hERG`, not attach) |
| models-train-solubility | Solubility_AqSolDB regressor | `ml_training/chemprop_train.nf` | ml_training | `f21eb10e-…` | failed — same TDC HTML | Route OK / exec **FAIL** (used `tdc:Solubility_AqSolDB`) |
| models-adapt-generative | Reinvent4 Finetune Rl | `…/reinvent4_finetune_rl/main.nf` | template_reuse | (route-only) | — | **PASS** route |
| models-adapt-finetune-property | Reinvent4 Finetune Rl | `…/reinvent4_finetune_rl/main.nf` | template_reuse | `44a1318f-…` | failed — same `logfile` | **FAIL** (wrong card) |
| models-optimise-dmt-loop | REINVENT4 Generative Lead Design | `…/reinvent4_lead_design/main.nf` | template_reuse | (route-only) | — | **DEV** — not DMTA (known product gap) |
| models-optimise-next-round | REINVENT4 Generative Lead Design | same | template_reuse | (route-only) | — | **DEV** — same |

No `undefined` card names; no `s3://` in card title/message. Remasure with explicit `session_datasets` in the public generate body still ignored on live tip (Node did not forward that field until local fix).

## Root causes

1. **Upload binding dropped for `generate_workflow` API**  
   Galaxy `generate_workflow_unified` set `uploaded_datasets = request.session_datasets or None` and ignored `available_datasets`. The public Node route only sent `datasets` → Galaxy `available_datasets`.  
   Effect: potency / fine-tune-property (no TDC alias) fall through → reinvent4_finetune_rl; herg/solubility route via alias and train on **TDC**, not the attached CSV — then Batch fails when TDC returns HTML.

2. **REINVENT4 transfer-learning TOML**  
   `_build_config` emitted `[logging] logfile=…`. Current REINVENT4 pydantic rejects it (`extra_forbidden`). Breaks Adapt / misrouted Train executes.

3. **Optimise / DMTA**  
   Catalog seeds a design–make–test loop, but chat still template-reuses lead design. Matches prior committee note (Rounds read-only / no launch). Not a catalog typo; product gap.

## Fixes landed (local; need sync for DEV)

| File | Change |
|------|--------|
| `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py` (+ packages mirror) | `uploaded_datasets = session_datasets or available_datasets` |
| `frontend/server/routes.ts` | Forward `session_datasets` / fall back to `available_datasets` |
| `frontend/server/galaxy-api-proxy.ts` | Promote upload-shaped `datasets` (with `s3_uri`) to `session_datasets` |
| `backend/lib/galaxy/ai/drug_discovery/reinvent4_trainer.py` | Drop forbidden `[logging] logfile` from TL TOML |
| `…/test_reinvent4_trainer.py` | Assert TL config omits logfile |

## Pass criteria after sync

- Potency + fine-tune-property → `ml_training/chemprop_train.nf`, `dataset=s3://…/bace_assays.csv`, `target_col=pIC50`, name not reinvent.
- herg/solubility → same chemprop path with **attached** S3 URI (not `tdc:*`).
- Adapt generative → reinvent4_finetune_rl; TL process no longer dies on logfile.
- Optimise may still be lead-design until DMTA launch ships — document, do not soft-pass.

## Commits

Focused Models coldstart wiring + REINVENT TL logfile fix committed this session (see git log).  
Related already on branch: `8493c1d891` / `2435bab3d2` (scaffold “diffusion train” re-arm).  
**Not synced to DEV yet** — remasure Train attach-S3 after PRE_SYNC + `scripts/sync_to_dev.sh`.
