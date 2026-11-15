# 2026-11-15 — Models surfaces: end-to-end test & fix plan

**Status:** plan only — do **not** implement product fixes, commit, or sync from this doc alone.  
**Await user commit** before any `git commit` / `scripts/sync_to_dev.sh`.  
**Ground truth:** `docs/20261115_COLDSTART_MODELS_MODULE_AUDIT.md` (DEV tip remasure `28e3dac5`); panel notes in `docs/20261112_MODELS_MODULE_COMMITTEE_AUDIT.md`, `docs/20261110_MODELS_PANEL_REBUILD.md`.  
**Fixture:** `lifeifei163361@163.com` · password from `E2E_FIXTURE_PASSWORD` / `~/.config/biomate/e2e_fixture_password` · auth header `x-e2e-test-token: biomate-e2e-bypass-token-dev-only` on DEV.  
**Harness pattern:** login once + one project; 90 s LLM timeouts; no mocked APIs; API remasure preferred over Playwright unless UI state must be screenshot-audited.

### Out of scope (explicit)

| Item | Why |
|------|-----|
| Design-module **“Optimise properties · one pass”** | Different cold-start module (`COLD_MODULES` Design track); not Models Optimise / DMTA |
| Cryo **402** license blocker | Known Data-analysis / cryo infra; not Models |

---

## 1. Goal & scope

**Goal:** Prove both Models product surfaces work end-to-end for every visible tab/track, then fix audit failures at root cause — never by routing DMTA to REINVENT4 lead design or inventing empty-state “success.”

**Surfaces in scope (“all through”):**

| Surface | Entry | Visible tracks / tabs | Actions that count as “through” |
|---------|-------|------------------------|----------------------------------|
| **A. Chat cold-start Models module** | Chat cold-start → Models | Train · Adapt · Optimise | Seed intent → workflow card (name + `nextflow_path` / product route) + correct fixture bind; route-only OK until Phase 5 |
| **B. Sidebar Models panel** | Sidebar → `/models` → `ModelsPanel` | Train · Model library · Molecular learning | Plan→execute (Train/Molecular), list/infer (Library), Rounds empty/read-only honesty (Molecular) |

**Hidden by design (verify stay hidden — do not “fix” by re-enabling):**

- House style / Adapt panel tab: `HOUSE_STYLE_HIDDEN = true` in `frontend/client/src/components/models/models-panel.tsx` (hooks remain for later IND editor pairing).

**“Through” does not mean** every path must hit AWS Batch on first pass. Phases 1–3 are cheap (unit / route / smoke). Phase 5 is gated expensive Batch after a written review note.

---

## 2. Phase 0 — inventory & contracts

**Do this before any product code.** Decision blocks Phase 4 Fix #1.

### 2.1 Product contract — DMTA / Optimise (PRIMARY)

**Ground truth today:**

- Cold-start Optimise seeds claim a design–make–test loop under a 96-assay budget (`cold-start-dashboard.tsx` + `cold-start-demo-catalog.ts` bundle `loop`).
- Chat routes both Optimise intents to **REINVENT4 Generative Lead Design** (`…/reinvent4_lead_design/main.nf`) — **not** DMTA.
- Real DMTA = CRO campaign Bayesian auto-retrain: `backend/lib/galaxy/ai/drug_discovery/auto_retrain.py`, `bayesian_optimizer.py`, API under `/api/drug-discovery/{campaign_id}/…` (`propose`, virtual-library cache, `refit_and_propose` / loop start), UI `drug-discovery-auto-retrain.tsx`.
- Panel Rounds (`RoundsSection` in `models-panel.tsx`) is **read-only**; empty copy (`models.rounds_empty`) tells the user to “Start a design–make–test–analyse loop” but the panel has **no** start/advance/stop controls — overclaim.

**Contract decision (pick exactly one before coding):**

| Option | Product meaning | Chat Optimise must… | Rounds must… |
|--------|-----------------|----------------------|--------------|
| **(A) Wire** | Optimise = campaign Bayesian DMTA | Create/attach campaign + propose/refit (or deep-link into CRO loop with same project + fixtures) — **never** `reinvent4_lead_design` | Show live rounds from `GET /api/model-tracks/optimise` **or** launch controls that call drug-discovery APIs |
| **(B) Honest** | Optimise is not launchable from Models chat yet | Catalog + assistant copy: “open CRO / Drug discovery campaign loop” (deep-link); **do not** seed “run the DMTA loop” as if chat executes it | Empty copy: no “start a loop” imperative; point to CRO campaign; no fabricated rounds |

**Anti-decision (forbidden):** treat `reinvent4_lead_design` as DMTA; stub fake rounds/scores in `models_inference.optimise_track`.

Record the choice in this doc’s “Decision log” section at execution time (append one line: date · A or B · owner).

### 2.2 Secondary contracts (lock pass criteria)

| Area | Contract | Pass when |
|------|----------|-----------|
| Cold-start **Train** | `ml_training` → `chemprop_train.nf`; dataset = attached project file (prefer literal `s3://…` after `_withS3Uri`); not `tdc:*`; not reinvent | Card name + path + `dataset` / `target_col` match audit table |
| Cold-start **Adapt generative** | `reinvent4_finetune_rl` | Path contains `reinvent4_finetune_rl` |
| Cold-start **Adapt property** | `chemprop_train.nf` + `bace_assays.csv` / `pIC50` | Same as Train potency bind |
| Panel **Molecular learning** train | Today: RDKit path (`sklearn_gbr` / `ludwig_molecular`) via `TrainingLauncher family="molecular"` | Either offer chemprop **or** copy/docs make RDKit vs chat-chemprop explicit (Phase 4 Fix #2) |
| Panel **Model library** | `GET /api/models`; infer `POST /api/models/:id/infer` | Honest empty for unowned Evo2 / unwired chemical — no fake evidence |
| Panel **Rounds** | `GET /api/model-tracks/optimise` → `{active: false}` or real loop | Matches contract A or B; read-only until A ships controls |
| House style | Hidden | Tab absent in DOM (`HOUSE_STYLE_HIDDEN`) |
| Soft naming | Solubility card | Prefer “solubility” / Delaney framing over `Solubility_AqSolDB` when training on `solubility.csv` |
| Soft UX | Train run link | Document or keep “open Run Manager” as intentional; no silent eject without link |
| Residual | `dataset` param | Literal `s3://${S3_BUCKET}/${s3_key}` after upload public shape sync |

### 2.3 Pass criteria per tab (checklist form)

**Chat cold-start**

| ID | Prompt (exact seed) | Bundle | Expected route | Fail if |
|----|---------------------|--------|----------------|---------|
| models-train-potency | Train a potency predictor on our in-house assay data. | `potency` | `chemprop_train.nf` | reinvent / TDC |
| models-train-herg | Train an hERG classifier and gate the design loop on it. | `herg` | `chemprop_train.nf` + `herg.csv` | `tdc:hERG` |
| models-train-solubility | Train a solubility model from our historical plate data. | `solubility` | `chemprop_train.nf` + `solubility.csv` | `tdc:Solubility_*` |
| models-adapt-generative | Adapt the generative model to our chemical series. | `molecules` | `reinvent4_finetune_rl` | lead_design / chemprop |
| models-adapt-finetune-property | Fine-tune this property predictor on our measured compounds. | `potency` | `chemprop_train.nf` | reinvent |
| models-optimise-dmt-loop | Run the design–make–test loop on this series under a 96-assay budget. | `loop` | Per Phase 0 A or B | lead_design while claiming DMTA |
| models-optimise-next-round | Propose the next round and refit on the results. | `loop` | Same as above | lead_design while claiming DMTA |

**Panel `/models`**

| Tab | Pass |
|-----|------|
| Train | Launcher plans (`POST /api/model-training/plan`); execute creates run; list via `GET /api/model-tracks/train`; cheap sklearn path preferred for smoke |
| Model library | List renders; empty catalog copy honest; structure (Boltz-2) infer path owned; genomic/chemical empty-state honest |
| Molecular learning | Launcher offers documented model types; Rounds empty matches contract; no launch button unless A |
| House style | Not visible |

---

## 3. Phase 1 — cheap verification matrix (no Batch)

Run locally before DEV remasure. Prefer existing tests; add only if a gap blocks Fix #n.

| Check | Command / how | Expected |
|-------|---------------|----------|
| Models cold-start catalog integrity | `cd frontend && npx vitest run client/src/components/cold-start-demo-catalog.test.ts` | All Models seeds present; `models:loop` share allowlist; demo assets non-empty |
| Static demo assets | Confirm files under `frontend/client/public/demo/cold-start/` for `bace_assays.csv`, `herg.csv`, `solubility.csv`, `candidate_library.csv`, Adapt molecule bundle | Non-empty, not HTML |
| Panel unit / i18n | `npx vitest run client/src/components/models/` | Launcher molecular → `sklearn_gbr`/`ludwig_molecular`; Rounds empty `data-testid=optimise-empty`; House style hidden |
| Project upload `s3_uri` contract | `npx vitest run server/project-routes.test.ts` | `_publicFile` / list emit `s3_uri` |
| Session dataset forward | Grep/tests in `server/routes.ts` / `galaxy-api-proxy.ts` (existing generate body tests if present) | `session_datasets` forwarded to Galaxy |
| Optimise track honesty | `cd backend && PYTHONPATH=lib python3.9 -m pytest …/test_models_inference_shape.py` (or project’s unit path for models_inference) | `{active: false}` when no campaign; no fabricated scores |
| Auto-retrain unit | `backend/lib/galaxy/ai/drug_discovery/tests/test_campaign_learning_loop.py` (+ `test_phase3_autoretrain_ind.py` if used) | `refit_and_propose` / propose shape OK |
| REINVENT TL logfile | `…/test_reinvent4_trainer.py` | TOML omits `[logging] logfile` |
| Typecheck | `cd frontend && npx tsc --noEmit -p .` | Exit 0 |
| Full vitest (pre-sync habit) | `cd frontend && npx vitest run` | Exit 0 |
| Galaxy import smoke (touched modules only) | `PYTHONPATH=lib python3.9 -c "import galaxy.webapps.galaxy.api.models_inference"` (+ `model_training_plan`, drug_discovery modules if edited) | Import OK |

**Do not** start Batch jobs in Phase 1.

---

## 4. Phase 2 — live DEV remasure (cheap LLM routes)

**Target:** `https://dev-public.biomate.ai`  
**Pattern:** one login, one project, upload cold-start fixtures once, generate per Models seed (route + dataset bind only — **no** execute/Batch).  
**Timeout:** ≥90 s per generate/chat-stream that needs a workflow card.  
**Reuse:** prior harness dirs under `/tmp/models_coldstart_*` as template; or extend API style of `scripts/e2e_models_tracks.sh` for tracks (that script covers panel tracks, not cold-start generate).

### 4.1 Setup

1. `POST /api/auth/login` with fixture email (never `/api/auth/register`).
2. `POST /api/projects` once → keep `projectId`.
3. Upload fixtures via `POST /api/projects/{id}/files/upload` from `frontend/client/public/demo/cold-start/`.
4. Assert upload JSON includes `s3_uri` (and `s3_key`). Fail Phase 2 residual check if `s3_uri` missing.
5. Generate with `session_datasets` (and/or promoted `datasets`) including filename + `s3_uri`.

### 4.2 Assertions (per row)

| Field | Assert |
|-------|--------|
| Card name | Non-empty, not `undefined` |
| `nextflow_path` / source | Matches Phase 0 table |
| `dataset` / training bind | Filename **or** literal `s3://…`; **not** `tdc:*` for herg/solubility/potency |
| `target_col` | potency / fine-tune: `pIC50`; herg: `IC50_nM` (or schema-equivalent); solubility: solubility / logS column as cataloged |
| Optimise | Per contract A/B — **fail** if lead_design while product still claims DMTA |

### 4.3 Evidence to keep

| Artifact | Content |
|----------|---------|
| Log dir | `/tmp/models_coldstart_remasure_<TS>/` — one JSON per seed (request + card summary) |
| Screenshots (optional if UI) | Chat: AI summary + workflow card for Train potency, Adapt generative, Optimise |
| Notes | DEV git tip / build-info; whether `s3_uri` appeared on upload |

**Pass Phase 2** when Train×3 + Adapt×2 match remasure PASS criteria in the cold-start audit, and Optimise is either correctly DMTA-wired (A) or honestly non-DMTA (B) — not silent lead_design under DMTA copy.

---

## 5. Phase 3 — panel smoke (`/models`)

Use same fixture session/project when possible. Prefer HTTP + light UI; screenshot empty/overclaim states.

| Step | How | Batch? | Pass / fail |
|------|-----|--------|-------------|
| Open `/models` | Browser or deep-link; tabs `data-testid=models-tabs` | No | Train · Library · Molecular visible; House style **absent** |
| Train plan→execute | UI launcher **or** `POST /api/model-training/plan` then execute with **sklearn_tabular** / small CSV | Prefer **no** GPU; local/CPU Batch only if unavoidable — flag | Plan accepted; runId appears; `GET /api/model-tracks/train` lists run |
| Train → Run Manager | Click run link after launch | No | Navigates to Run Manager / chat run (document as soft UX; not a P0 fail unless broken) |
| Model library list | `GET /api/models` | No | Array or honest empty catalog string |
| Library infer — structure | Boltz-2 only if Phase 5 approved; else skip execute | **Yes if fold** | Smoke: model visible with owned origin; do not claim NVIDIA for Boltz-2 |
| Library infer — genomic | Select Evo2 if listed | No (expect block) | Honest empty / unavailable — **not** fabricated genomic evidence (`models_inference` hides pure NVIDIA until owned) |
| Library infer — chemical | Catalog chemical slot | No | Honest “no chemical model wired” / empty — not stub success scores |
| Molecular launcher | `TrainingLauncher family="molecular"` + SMILES CSV | Cheap sklearn_gbr OK | Plan `model_type=sklearn_gbr` (or ludwig_molecular); document chemprop gap |
| Rounds empty | Fresh project, `GET /api/model-tracks/optimise` + UI `optimise-empty` | No | Copy matches contract B **or** A-with-CTA; must not imply in-panel start if no controls |
| Existing track e2e | `BIOMATE_URL=https://dev-public.biomate.ai ./scripts/e2e_models_tracks.sh` | Retrain may schedule work — review script before run | Honest-empty + adapt toggle persist; log under `docs/e2e_runs/` |

**Flag for Phase 5:** reinvent finetune, chemprop_train on Batch, Boltz fold, Adapt retrain GPU.

---

## 6. Phase 4 — fix order (root cause only)

Implement only after Phase 0 decision. **Do not commit unless user asks.** Each fix: code + acceptance test + “do not” list.

### Fix 1 — DMTA contract (PRIMARY)

**Files (touch set depends on A vs B):**

| Path | Role |
|------|------|
| `frontend/client/src/components/cold-start-dashboard.tsx` | Optimise seed copy |
| `frontend/client/src/components/cold-start-demo-catalog.ts` | `loop` context / expected product |
| `frontend/server/galaxy-assistant.ts` | Routing: DMTA vs generative design disambiguation |
| `frontend/client/src/components/models/models-panel.tsx` | `RoundsSection` CTA / honesty |
| `frontend/client/src/locales/en/common.json` (+ `zh`) | `models.rounds_empty` / heading |
| `backend/lib/galaxy/webapps/galaxy/api/models_inference.py` | `optimise_track` read path |
| `backend/lib/galaxy/ai/drug_discovery/auto_retrain.py` | Real loop |
| `backend/lib/galaxy/ai/drug_discovery/bayesian_optimizer.py` | Propose |
| `backend/lib/galaxy/ai/drug_discovery/api_router.py` | `/propose`, loop start/stop, virtual library |
| `frontend/client/src/components/drug-discovery-auto-retrain.tsx` | CRO UI bridge / deep-link target |

**(A) Wire acceptance**

1. Cold-start Optimise generate does **not** return `reinvent4_lead_design`.
2. Happy path: campaign exists or is created; propose/refit returns proposal shaped for Rounds **or** UI deep-links to CRO auto-retrain with same project + `loop` fixtures.
3. `GET /api/model-tracks/optimise` returns active loop after propose (not forever `{active:false}` when campaign has proposals).
4. Unit: routing test + `test_campaign_learning_loop` still green.

**(B) Honest acceptance**

1. Catalog / dashboard copy no longer promises in-chat DMTA execution.
2. Assistant routes Optimise intent to deep-link / guidance, not lead_design-as-DMTA.
3. `rounds_empty` removes false “Start a … loop” imperative (or points to CRO).
4. Remasure Optimise: explicit **PASS (honest)** not **DEV gap**.

**Do not:** map “design–make–test” → `reinvent4_lead_design`; fabricate Rounds scores; hide the gap by deleting Optimise seeds without replacing honesty.

### Fix 2 — Molecular learning vs chemprop surface mismatch

**Files:** `training-logic.ts`, `training-launcher.tsx`, `training-specs.ts`, optional `model_training_plan.py` / ml_training plan; docs note in this file or short `docs/20261115_…` follow-up.

| Path | Choose one |
|------|------------|
| **2a Offer chemprop** | Add chemprop to molecular launcher / plan API; acceptance: molecular plan can emit `chemprop_train.nf` |
| **2b Document** | UI helper text: “Panel Molecular = RDKit (sklearn_gbr / ludwig); chat Train = chemprop” |

**Do not:** silently route panel molecular to reinvent; claim panel trains chemprop without a plan path.

### Fix 3 — Model library genomic / chemical empty

**Files:** `models_inference.py` (catalog + `_stub_result` / hide NVIDIA), Library UI empty states, i18n.

**Acceptance:** Evo2 not presented as runnable owned model; chemical infer returns clear unwired empty; structure Boltz-2 remains owned Batch path.

**Do not:** stub genomic/chemical evidence classes with fake measured values.

### Fix 4 — Soft: naming, Run Manager eject, Adapt hidden

| Item | Files | Acceptance | Do not |
|------|-------|------------|--------|
| Solubility card name | assistant naming / ml_training card title path | Prefer Delaney/`solubility.csv` framing over `Solubility_AqSolDB` when not using TDC | Reintroduce `tdc:Solubility_AqSolDB` bind |
| Train → Run Manager | `training-launcher.tsx`, `models-panel.tsx` `openRunManager` | Document as intentional **or** keep inline status; link must work | Remove run visibility without replacement |
| Adapt / House style hidden | `HOUSE_STYLE_HIDDEN` | Remains hidden; Adapt cold-start stays chat-only | Re-enable empty House tab “to match chat” |

### Fix 5 — Residual literal `dataset=s3://`

**Files:** `frontend/server/project-routes.ts` (`_withS3Uri`), generate/execute staging in `routes.ts`, select_training_dataset path in Galaxy AI assistant.

**Acceptance:** After upload, remasure Train potency shows `dataset` starting with `s3://` (or documented equivalent bind that execute stages). Vitest `project-routes.test.ts` green. Sync frontend layer before claiming met.

**Do not:** strip `s3://` in prompts “to pass” filename-only checks; skip sync and call residual fixed.

### Suggested implementation order

1 → 5 (s3_uri if not yet on DEV tip) → 3 → 2 → 4 soft.  
Always: Phase 0 decision before 1.

---

## 7. Phase 5 — expensive Batch (gated)

**Hard gate:** complete Phase 4 code review note (below template) **before** any `docker restart` / sync / GPU job.

### 7.1 Review note template (fill before launch)

```
Change: <1 paragraph — what landed for Fixes 1–5>
Gating conditions: <which ifs must be true for Batch path>
Data flow: <project files → session_datasets → plan/execute → Batch>
Silent skips: <what returns empty without error>
Predicted smoke result: <card/run terminal expectation>
Cost/time budget: <cap>
```

### 7.2 Allowed expensive runs (only if predicted pass)

| Run | Trigger | Why expensive | Gate |
|-----|---------|---------------|------|
| REINVENT4 finetune RL | Adapt generative execute | GPU + long | Route already PASS; TL TOML logfile-free; `n_steps`/budget minimized |
| chemprop_train Batch | Train potency/herg/solubility execute | GPU/CPU Batch | `dataset` attached (not TDC); small epochs if configurable |
| Boltz fold | Library structure infer | GPU | Owned Batch path only; skip if library smoke already covered elsewhere |
| Adapt track retrain | `POST /api/model-tracks/adapt/retrain` | May schedule training | Only after `e2e_models_tracks.sh` review |

**Abort if:** prediction unclear; MemStorage/state wiped mid-test; would need >1 speculative redeploy to “see what happens.”

---

## 8. Phase 6 — sync & regression

1. **Pre-sync** (`docs/PRE_SYNC_CHECKLIST.md`):
   - `cd frontend && npx tsc --noEmit -p .`
   - `cd frontend && npx vitest run`
   - For every touched `backend/lib/galaxy/**/*.py`:  
     `cd backend && PYTHONPATH=lib python3.9 -c "import galaxy.webapps.galaxy.api.<module>"`  
     (at minimum `models_inference`; also drug_discovery import paths if Fix 1A).
2. **Await user commit** — then push/commit only if user requests.
3. `scripts/sync_to_dev.sh` (code-only unless DB change required; note `BIOMATE_SYNC_DB`).
4. **Re-remasure:** Optimise (contract A/B) + Train×3 + Adapt×2 on DEV tip.
5. Update `docs/20261115_COLDSTART_MODELS_MODULE_AUDIT.md` (new tip, verdict table, Optimise status Met/Honest).
6. Append Decision log + remasure tip to **this** plan doc.

---

## 9. Exit criteria checklist

- [ ] Phase 0 DMTA decision recorded (A or B)
- [ ] Phase 1 cheap matrix green (tsc + vitest + relevant py imports/tests)
- [ ] Phase 2: Train×3 + Adapt×2 route+bind PASS on DEV (fixture email, one project)
- [ ] Phase 2/4: Optimise is **not** lead_design-presented-as-DMTA (wired **or** honest)
- [ ] Phase 3: `/models` tabs smoke; House style hidden; Rounds copy matches contract
- [ ] Fix 2: chemprop offered on Molecular **or** documented mismatch
- [ ] Fix 3: genomic/chemical empty states honest (Evo2 not owned; chemical unwired)
- [ ] Fix 5: Train potency remasure shows literal `s3://` dataset (or explicitly closed with execute-staging proof)
- [ ] Soft items triaged (solubility naming; Run Manager link intentional)
- [ ] Phase 5 only after written review note; no speculative GPU loops
- [ ] Phase 6 pre-sync checklist + DEV remasure + audit doc updated
- [ ] Design one-pass Optimise + Cryo 402 still out of scope (unchanged)
- [ ] No commit/sync performed from plan-only work without user ask

---

## Decision log (append at execution)

| Date | Decision | Owner | Notes |
|------|----------|-------|-------|
| 2026-11-15 | **A (Wire)** | agent | Models Rounds: create campaign + start/stop/trigger via drug-discovery retrain APIs (campaign_id = project id). Chat Optimise: `isDmtaLoopQuery` early-return deep-link `/models?tab=molecular` — never reinvent4_lead_design. Dead `/drug-discovery-cro` links retargeted. Session: `docs/20261115_MODELS_PANEL_UX_IMPROVEMENTS.md`. |
| 2026-11-15 | **A restore + ingest** | agent | Prior A WIP had been stashed (`Models DMTA honesty (exclude from coldstart Commit A sync)`) and was missing from HEAD; restored from `stash@{0}` (+ untracked `dmta-rounds.tsx`). Added loop-fixture assay ingest + virtual-library seed on create, and a dedicated multipart ingest-assay Node proxy (wildcard previously dropped the file body). |

## Key file / route index (quick ref)

| Concern | Location |
|---------|----------|
| Cold-start Models UI | `frontend/client/src/components/cold-start-dashboard.tsx` (`COLD_MODULES` id=`models`) |
| Demo bundles | `frontend/client/src/components/cold-start-demo-catalog.ts` |
| Chat routing | `frontend/server/galaxy-assistant.ts` |
| Models panel | `frontend/client/src/components/models/models-panel.tsx` |
| Launcher | `training-launcher.tsx`, `training-logic.ts` |
| Client APIs | `models-api.ts` → `/api/models`, `/api/model-tracks/*`, `/api/model-training/plan` |
| Node proxy | `frontend/server/routes.ts` (~5744+) |
| Galaxy models API | `backend/lib/galaxy/webapps/galaxy/api/models_inference.py` |
| Training plan | `backend/lib/galaxy/webapps/galaxy/api/model_training_plan.py` |
| DMTA engine | `auto_retrain.py`, `bayesian_optimizer.py`, `api_router.py` |
| CRO UI | `drug-discovery-auto-retrain.tsx` |
| Panel tracks e2e | `scripts/e2e_models_tracks.sh` |
| Prior audit | `docs/20261115_COLDSTART_MODELS_MODULE_AUDIT.md` |
