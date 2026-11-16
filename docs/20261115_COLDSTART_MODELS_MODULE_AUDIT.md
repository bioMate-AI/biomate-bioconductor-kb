# 2026-11-15 — Cold-start Models module audit + DEV test

**DEV tip (live):** `28e3dac52cbd311de7c2e7f411142c09ce02b37e`  
**Prior tip (pre-fix harness):** `cb472efe5c13d798b67e02aa642e088e1bdf9847`  
**Fixture:** `lifeifei163361@163.com` (password from `~/.config/biomate/e2e_fixture_password`, not printed)  
**Harness:** API (login once, one project) — Playwright deep suite skipped (local disk / Chrome risk; API pattern matches `design-generate-sm-0`)  
**Evidence (pre-fix):** `/tmp/models_coldstart_harness_20261115T121101Z/`, `/tmp/models_coldstart_session_ds_20261115T122334Z/`  
**Evidence (post-sync remasure):** `/tmp/models_coldstart_remasure_20261115T141507Z/`  
**Sync log:** `/tmp/biomate_sync_to_dev_2c2233c042_codeonly_20261115_140255.log` (`BIOMATE_SYNC_DB=0`, SYNC_RC=0)

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

## DEV API results — pre-fix (tip `cb472efe`)

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

## DEV API remasure — post-sync (tip `28e3dac5`)

Hostname TLS (`https://dev-public.biomate.ai`). Login once + project `c7878fd2-…`. Route + dataset-binding only (no Batch exec). Uploads via `/api/projects/{id}/files/upload` (returns `id` + `s3_key`, no `s3Uri` field).

| id | Card name | nextflow_path | source | dataset | target_col | Verdict |
|----|-----------|---------------|--------|---------|------------|---------|
| models-train-potency | potency predictor | `ml_training/chemprop_train.nf` | ml_training | `bace_assays.csv` (not reinvent) | `pIC50` | **PASS** route |
| models-train-herg | hERG classifier | `ml_training/chemprop_train.nf` | ml_training | `herg.csv` (**not** `tdc:hERG`) | `IC50_nM` | **PASS** attach (filename, not TDC) |
| models-train-solubility | Solubility_AqSolDB regressor | `ml_training/chemprop_train.nf` | ml_training | `solubility.csv` (**not** `tdc:Solubility_*`) | `solubility` | **PASS** attach (filename, not TDC) |
| models-adapt-generative | Reinvent4 Finetune Rl | `…/reinvent4_finetune_rl/main.nf` | template_reuse | — | — | **PASS** route |
| models-adapt-finetune-property | property predictor | `ml_training/chemprop_train.nf` | ml_training | `bace_assays.csv` | `pIC50` | **PASS** route |
| models-optimise-dmt-loop | REINVENT4 Generative Lead Design | `…/reinvent4_lead_design/main.nf` | template_reuse | — | — | **DEV** — not DMTA (known product gap) |
| models-optimise-next-round | REINVENT4 Generative Lead Design | same | template_reuse | — | — | **DEV** — same |

### Remasure notes

- Live Galaxy confirms `uploaded_datasets = request.session_datasets or request.available_datasets or None` (lines ~4184 / ~4706). Frontend `/app/dist/index.js` forwards `session_datasets`.
- Generate `dataset` is the **attached project filename**, not a `tdc:*` alias and not a literal `s3://…` URI. Project upload API surfaces `s3_key` (`projects/<pid>/inputs/<file>`); execute staging resolves that key to Batch-readable S3. Residual vs the strictest pass-criteria wording (`dataset=s3://…`) — binding is by uploaded name/id, not URI string in the card params.
- REINVENT TL TOML no longer emits `[logging] logfile=` (verified on live container). Batch remasure of Adapt generative not re-run this pass (route-only).
- Harness logged `UPLOAD … s3 None keys […, 's3_key', …]` for every file — see root cause **#4** below (not IAM / disk / swallowed put).

## Root causes

1. **Upload binding dropped for `generate_workflow` API**  
   Galaxy `generate_workflow_unified` set `uploaded_datasets = request.session_datasets or None` and ignored `available_datasets`. The public Node route only sent `datasets` → Galaxy `available_datasets`.  
   Effect: potency / fine-tune-property (no TDC alias) fall through → reinvent4_finetune_rl; herg/solubility route via alias and train on **TDC**, not the attached CSV — then Batch fails when TDC returns HTML.

2. **REINVENT4 transfer-learning TOML**  
   `_build_config` emitted `[logging] logfile=…`. Current REINVENT4 pydantic rejects it (`extra_forbidden`). Breaks Adapt / misrouted Train executes.

3. **Optimise / DMTA**  
   Catalog seeds a design–make–test loop, but chat still template-reuses lead design. Matches prior committee note (Rounds read-only / no launch). Not a catalog typo; product gap.

4. **Project upload public shape omitted `s3_uri`** (tip `28e3dac5` remasure)  
   `POST /api/projects/:id/files/upload` **succeeded** (HTTP 201, objects present under `s3://biomate-nextflow-work/projects/<pid>/inputs/…`, content_hash set). `_publicFile` projected DB columns only (`s3_key`, …) and never derived `s3_uri`. Harness therefore sent session_datasets without URI → `select_training_dataset` fell back to the filename → attach criterion `dataset=s3://…` failed for potency/herg/solubility/finetune-property.  
   Ruled out: IAM (put succeeded), DEV disk-full (local multer temp only; S3 put OK; EC2 root ~98% but orthogonal), sanitization of a failed URI (there was none to strip).  
   Fix: `_withS3Uri` on upload/list public rows (`s3://${S3_BUCKET_NAME}/${s3_key}`); execute also stages app-bucket URIs when `S3_BUCKET_NAME ≠ NEXTFLOW` bucket.

## Fixes landed + synced

| File | Change |
|------|--------|
| `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py` (+ packages mirror) | `uploaded_datasets = session_datasets or available_datasets` |
| `frontend/server/routes.ts` | Forward `session_datasets` / fall back to `available_datasets`; stage app-bucket `s3://` params when Batch bucket differs |
| `frontend/server/galaxy-api-proxy.ts` | Promote upload-shaped `datasets` (with `s3_uri`) to `session_datasets` |
| `frontend/server/project-routes.ts` | Derive `s3_uri` on upload/list public file shape |
| `frontend/server/project-routes.test.ts` | Contract: `_publicFile` / list emit `s3_uri` |
| `backend/lib/galaxy/ai/drug_discovery/reinvent4_trainer.py` | Drop forbidden `[logging] logfile` from TL TOML |
| `…/test_reinvent4_trainer.py` | Assert TL config omits logfile |

Synced to DEV as tip `28e3dac5` (ancestry includes `3536d04b05` + `2c2233c042` + merge of live `cb472efe`). Layers: frontend + backend; `BIOMATE_SYNC_DB=0`.  
`s3_uri` public-shape fix: pending sync after this commit (see remasure § below once tip advances).

## Pass criteria (status after remasure)

| Criterion | Status |
|-----------|--------|
| Potency + fine-tune-property → `chemprop_train.nf`, not reinvent | **Met** |
| `target_col=pIC50` on potency / fine-tune | **Met** |
| herg/solubility → chemprop with **attached** data (not `tdc:*`) | **Met** (filename bind on `28e3dac5`; literal `s3://` after `s3_uri` fix) |
| Generate param is literal `s3://…` URI | **Not met on `28e3dac5`** — fixed in tree (`_withS3Uri`); remasure after frontend sync |
| Adapt generative → reinvent4_finetune_rl | **Met** (route) |
| Optimise → DMTA | **Met & verified on DEV `77969b9c`** (deep-link to `/models?tab=molecular`, no reinvent4 card) — superseded the old "Open" verdict, which was measured on pre-`029383bad6` tip `28e3dac5`. See CORRECTION section. |

## Commits

Focused Models coldstart wiring + REINVENT TL logfile fix: `3536d04b05`.  
Related already on branch: `8493c1d891` / `2435bab3d2` (scaffold “diffusion train” re-arm); phase-map `2c2233c042`.  
Sync merge tip on DEV: `28e3dac5`.  
Project upload `s3_uri` public-shape: this follow-up commit (see git log).

---

## CORRECTION (2026-11-15, later session) — Option A DMTA UX IS deployed on DEV

**The "Optimise → DMTA: Open product gap (still lead-design)" verdict above is STALE.** It was measured on DEV tip `28e3dac5`, which predates the Option A DMTA wiring commit `029383bad6` ("restore Option A DMTA UX and seed propose fixtures") by three deploys. On that old tip Optimise still returned `reinvent4_lead_design` — expected, because the deep-link/refuse code did not yet exist.

**Deployment proof (not the ledger title — the actual sync payload):**

- DEV advanced to `77969b9c` at **2026-11-15T16:49:28Z** via `sync_to_dev.sh`.
- That sync used **diff base `a5ace834 → 77969b9c` (25 code files), `Layers: frontend=true backend=true workflows=true db=false`**, health-verified, ledger recorded at 10:49:33 local (`/tmp/sync_coldstart_scfv_cyclic_20261115j.log`).
- `029383bad6` sits **between** `a5ace834` and `77969b9c`, so **every file `029383bad6` touched (21 files; ~19 Models-related)** is inside `git diff --name-only a5ace834ed 77969b9c6a` — all of `components/models/*` (incl. `dmta-rounds.tsx`, `dmta-loop-fixtures.ts`, `models-panel.tsx`, `training-logic.ts`, `run-pretrained.tsx`, `training-launcher.tsx`), plus `routing-authority.ts`, `galaxy-assistant.ts`, `routes.ts`, `ai_assistant.py`, `cold-start-demo-catalog.ts`, locales, and 5 Models test files. The whole Option A payload shipped under `frontend=true backend=true`.
- The 2026-11-15 ~12:44 "all layers false" sync attempt was a **no-op because DEV was already at `77969b9c`** (`/tmp/biomate_models_sync.log`: "ancestry verified: 77969b9c -> 77969b9c", Diff base `77969b9c → 77969b9c` (1 file), all layers false), not a failed Models deploy. The 20261115 takeoff doc's "Models UX not deployed" premise is therefore incorrect.

**Confirmed this session:** DEV reachable (HTTP 200); `GET /build-info.json` on DEV returns `{"commit":"77969b9c…"}` (frontend bundle live at that tip); the `77969b9c` sync log shows the frontend image **built + promoted** ("verified public build commit 77969b9c…") and the backend gunicorn **restarted with a fresh module load** (bytecode cache cleared) — so the deployed code is actually running, not an inert/cached copy. No feature flag gates the DMTA path (`MODELS_DMTA_HREF` is a plain constant; `isDmtaLoopQuery` / `_is_dmta_loop_task` are regex with no env check). Local pre-sync checklist green on the tree containing `029383bad6`: `tsc` no errors (empty log; `TSC_EXIT=0` in-shell), `vitest` 4016 passed / 0 failed, `galaxy.ai.ai_assistant` import OK (in-shell).

**This correction was independently audited this session by a 3-agent adversarial committee** (deployment-claim / reasoning-gaps / doc-accuracy); all three confirmed the deployment and that the deployed commit == the good 293-line `dmta-rounds.tsx` (not a degraded stash restore).

### Behavioral remasure on live DEV (`77969b9c`) — NOW DONE, GREEN

Ran against `https://dev-public.biomate.ai` with the canonical fixture (one login, one project per probe; `/api/chat/stream`). Evidence dirs under `/tmp/models_optimise_remasure_*` and `/tmp/reinvent_route_*`.

| Probe | Query | Result | Verdict |
|-------|-------|--------|---------|
| Optimise seed 1 | "Run the design–make–test loop … under a 96-assay budget." | `state:chat_only`, `workflow:null`, **no** `workflow_ready`, message deep-links to `/models?tab=molecular`; reasoning "DMTA loop → Models Rounds (not reinvent4_lead_design)" | **PASS** (needed 180s client budget — heavier intent decomposition; routing itself is deterministic regex) |
| Optimise seed 2 | "Propose the next round and refit on the results." | same as above; completed in ~5.7s | **PASS** |
| Reinvent4 routing (complement) | "Use REINVENT4 to generate 100 novel drug-like analogs … de novo generative lead design." | `state:workflow_ready`, full **REINVENT4 Generative Lead Design** card (Validate → Generate → BRICS → Filter/Rank → Report) | **PASS** — genuine generative intent still reaches reinvent4; distinction works both ways |

So the Optimise→DMTA deep-link and the invent4 refuse path are confirmed **live on DEV**, not just deployed. (One test-design note: a query literally containing the word "DMTA" trips the deep-link regex regardless of generative intent — expected.)

### Reinvent4 execution fixes — verified on DEV (minimal Batch run)

All six fixes are ancestors of the deployed `77969b9c`: `82cccf5565` (procps), `dc5ebab226` (`prior_path` optional), `de208a32bb`/`4867407ddb` (`"""` scrub from Nextflow script), `c0fe0249ea` (reinvent4-nf layout bridge), `3536d04b05` (TL logfile). Launched `reinvent4_lead_design` via `POST /api/workflows/execute` with minimized params (`n_steps=20`, `batch_size=16`, `top_n=20`, CPU):

- **runId** `388bb16a-b12e-442e-b720-89308668854d` — **completed, 5/5 steps**, ~4.5 min.
- **13 real S3 outputs** (`biomate-nextflow-work`): `top_compounds.csv` (real SMILES + score/qed/sa/mw/scaffold, e.g. rank 1 `N#Cc1ccc(N2CCC(C(=O)Nc3ccncc3)CC2)cc1F` score 0.905), `top_compounds.sdf` (41 KB), `raw_molecules.csv` (generated pool), `score_trajectory.png`, `reinvent.log`, `report.html` (3 MB), `design_report.html`, `design_summary.json`, `filter_stats.json`, `qc_events.json`, etc.
- Proves the workflow now parses and the Generate step runs to completion with genuine generative output (the failure modes those commits fixed no longer occur). Test project `b09747ee-…` left intact as the evidence trail.

**Remaining open item:** DEV **behavioral** remasure of the two Optimise seeds on the live `77969b9c` build — confirm no `reinvent4_lead_design` card and a deep-link/guidance to `/models?tab=molecular`. Code is deployed but the live behavior has not been re-measured since the old-tip audit. Verdict pending (this session).
