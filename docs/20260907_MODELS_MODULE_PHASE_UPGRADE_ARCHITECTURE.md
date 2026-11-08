# Models Module — Phase Upgrade: Architecture & Function-Level Reference

**Date:** 2026-09-07
**Branch / PR:** `feat/models-real-tracks` → PR #212 (base `feat/dl-upgrade-wave3`)
**Builds on:** `docs/20260905_CLAUDE_DESIGN_IMPLEMENTATION_GAP_INVENTORY.md`
(the pre-upgrade audit that scored Models spec-03 at ~22–25%), the reference
design `reference/claude_design/data_centroid_design/dataui/Models.jsx` +
`ModelObject.jsx`, and `docs/20260901_MODELS_TRACKS_WHY_GALAXY_NOT_NEXTFLOW.md`
(the tier-placement rationale).

**Status:** implemented, unit-green, on the PR branch; not yet synced to dev.
This document is the authoritative architecture + function-level reference for
the phase and the input to the team test plan
(`docs/20260907_MODELS_MODULE_TEST_PLAN.md`).

---

## 0. What this phase delivered (against the gap inventory)

The pre-upgrade audit (2026-09-05) scored **Models (spec 03) at ~22–25%**:

> 5 tracks present as tabs, but **Train / Adapt / Optimise are placeholder cards**
> … the **Model Object** ~40%: lineage/consumers/versions degraded from clickable
> objects to bare strings; no Supersede / Use-in-a-run; no interface signature;
> no version compare. Breaks the spec's "objects, not strings" discipline.

This phase closes that line to **all five tracks real + the Model Object
restored to objects-not-strings + the tracks wired to live data + interactive
controls persisted + retrains surfaced as first-class runs**. The one remaining
spec-03 gap is called out honestly in §7 (the full `WetLabRound` §3.7 wet-lab
loop, and GPU LoRA on Batch).

### Commit map (phase = `8a562b82b` … `31d7749f0`, 9 commits)

| Commit | Layer | What |
|---|---|---|
| `8a562b82b` | FE | Model Object objects-not-strings + real Optimise/DMTA track |
| `5d66957e5` | FE | Re-export Optimise DMTA types from module index |
| `e5f30c61c` | FE | Real Train track (loop · runs · families) |
| `f40324f8a` | FE | Real Adapt track (level ladder · switchable pairs) |
| `1f855f1e8` | BE+FE | Self-fetching Train/Adapt/Optimise over real WS1 stores |
| `8ed9d7888` | BE+FE | Persist Adapt toggle + retrain (mutation endpoints) |
| `31f719274` | BE | Retrain advances via worker tick + Train shows adaptation jobs |
| `9416c9ac0` | Node | Adapt retrain registers a first-class run in the dashboard |
| `31d7749f0` | docs | Tier-placement architecture note |

---

## 1. Layered architecture

```
Browser (React)                         Node/Express                    Galaxy (FastAPI)                 Real stores
──────────────                          ────────────                    ───────────────                 ───────────
components/models/*                      server/routes.ts                webapps/.../models_inference.py
  ModelsPanel ─ tab tracks                _dlProxyHandler ──────────────►  GET  /api/model-tracks/train ──► custom_model_registrations (per-campaign SQLite)
    TrainTrack   ◄─ useTrainTrack ──────► (proxy /api/model-tracks/*)      GET  /api/model-tracks/adapt ──► regulatory_pair_recorder JSONL + disabled_pairs.jsonl
    AdaptTrack   ◄─ useAdaptTrack                                          GET  /api/model-tracks/optimise ► auto_retrain.list_auto_proposals (campaign DB)
    OptimiseTrack◄─ useOptimiseTrack                                       POST /adapt/{id}/toggle ───────► disabled_pairs.jsonl (append-only override)
    RegistryTrack◄─ useModels ─────────► (proxy /api/models*)             POST /adapt/retrain ───────────► regulatory_training_jobs.submit + worker.tick
    RunPretrained◄─ useInfer            _adaptRetrainHandler ────────────► (proxy) then storage.createExecutionRun (Postgres execution_runs)
  ModelObject   ◄─ useModel ──────────► (proxy /api/models/:id)           GET  /api/models/:id
```

**Tier placement rationale** (full doc:
`20260901_MODELS_TRACKS_WHY_GALAXY_NOT_NEXTFLOW.md`): endpoints live in the
Galaxy FastAPI app because that is BioMate's API tier (auto-discovered via
`include_all_package_routers`). They are **not** Nextflow, because the reads are
state and the default retrain is a sub-second CPU compile — Batch/Nextflow would
be wrong on cost/latency/domain-fit. The single heavy path (GPU LoRA) is gated
and out of scope (§7).

**Route-collision design:** all track routes use the distinct
`/api/model-tracks/*` prefix so they never fall under the greedy
`/api/models/{model_id:path}` detail route. On the Node side, the specific
`POST /api/model-tracks/adapt/retrain` is registered **before** the generic
`/api/model-tracks/*` proxy so it can register a run; everything else falls
through to the shared proxy.

---

## 2. Frontend — function-level reference

### 2.1 `components/models/model-object.tsx` — objects, not strings

The Model Object presents a model like a dataset (identity · evidence · lineage ·
consumers · interface · versions). This phase restored the "objects, not strings"
discipline the gap inventory flagged as broken.

| Symbol | Signature | Role |
|---|---|---|
| `verdictColor(verdict)` | `(string) → string` | pass=green / fail=red / else grey. |
| `GateVerdict({verdict})` | component | The measured·threshold·verdict pill. |
| `fmt(v)` | `(string\|number\|null) → string` | `—` for null/undefined. |
| `ifaceSignature(iface)` | `(ModelDetail["interface"]) → string` | The call-signature line. Uses `iface.signature` if the backend supplies one, else derives an honest generic shape from `kind` (`python→call(inputs)->result`, `container→run(...)`, `rest→POST /infer {inputs} -> result`). **Never a fabricated per-model signature.** |
| `ModelObject({detail, modelId, onBack, className, onOpenData, onOpenRun, onOpenModel, onOpenConsumer, onCompareVersion, onUseInRun, onSupersede})` | component | The object surface. New callbacks make lineage/consumer/version rows into **clickable objects**; degrade to plain text when a value or callback is absent. Header gains **"Use in a run"** (`onUseInRun`) + **"Supersede"** (`onSupersede`). |
| `ModelObjectLoader({modelId, onBack, className, ...actions})` | component | Fetches by id (`useModel`) then renders; forwards all action callbacks. |

**Objects-not-strings, tab by tab:**
- **Lineage:** dataset (`onOpenData`), training-run (`onOpenRun`), prior versions
  (`onOpenModel`) are clickable links (`data-testid` `lineage-dataset-link` /
  `lineage-run-link` / `lineage-prior-{v}`) when both a value and a callback
  exist; else plain `fmt()` text.
- **Used by (consumers):** each string is parsed into `kind · where · how`
  (splitting on `·` and a `kind:where` prefix), with an **"open →"**
  (`onOpenConsumer`, testid `model-consumer-open-{c}`). Honest: when the string
  has no structure, the whole string is `where` and kind defaults to `consumer`.
- **Interface:** adds the `ifaceSignature` line (testid `model-iface-signature`).
- **Versions:** marks the current version and adds a per-version **compare**
  affordance (`onCompareVersion`, testid `model-version-compare-{v}`).

### 2.2 `components/models/models-panel.tsx` — the 5-track surface

Exported track data types (also re-exported from `index.ts`):
`OptimiseData`/`OptimiseSurrogate`/`OptimiseRound`/`OptimiseProposal`,
`TrainData`/`TrainRun`, `AdaptData`/`AdaptPair`.

| Symbol | Role |
|---|---|
| `MODELS_TRACKS` | `["Train","Adapt","Optimise","Run a pre-trained model","Registry"]`. |
| `RegistryTrack({onOpenModel})` | Live `useModels()` catalog table; a row opens the Model Object. |
| `OptimiseTrack({data, onOpenModel})` | DMTA loop: header (running/round), surrogate model links (`onOpenModel`), rounds list, and the **proposal table** (id/score/confidence/verdict) where **safety-gate rejections stay visible** (red). Honest empty state (`optimise-empty`) when `data` is absent. |
| `proposalVerdictColor(verdict)` | accepted=green / `/reject/i`=red / else amber. |
| `TrainTrack({data, onOpenModel})` | Training-loop diagram + families (fixed design content) + training-runs list (status/gate/metric/dataset + "watch live →"/"open experiment →"). Honest empty (`train-runs-empty`). |
| `trainStatusColor(status)` | completed=green / failed=red / running=blue / else grey. |
| `AdaptTrack({data, onToggleLearned, onRetrain})` | Level ladder (rule→index→adapter, fixed) + "Re-train on my edits" (`onRetrain`, with pending count) + switchable before→after pairs (red strikethrough → green, toggle fires `onToggleLearned`). Honest empty (`adapt-learned-empty`). |
| `ModelsPanel({project, tab, onTabChange, className, trainData, adaptData, onAdaptToggle, onAdaptRetrain, optimiseData})` | The panel. Self-fetches track data as defaults (`useTrainTrack`/`useAdaptTrack`/`useOptimiseTrack`); **an explicit prop always overrides the fetched default**. Defaults `onAdaptToggle`/`onAdaptRetrain` to the persisted mutations (`useAdaptToggle`/`useAdaptRetrain`); a parent prop still overrides. Opening a model takes over the whole surface via `ModelObjectLoader`. |

**Prop-vs-fetch precedence (important for testing):**
`effectiveTrainData = trainData ?? fetchedTrain` (and same for adapt/optimise).
`projectArg = project === "Project" ? undefined : project` — the default
placeholder project name does not trigger a project-scoped fetch.

### 2.3 `components/models/models-api.ts` — react-query hooks

| Hook | Endpoint | Returns / behaviour |
|---|---|---|
| `useModels()` | `GET /api/models` | Catalog array; `[]` on non-array/`!ok`. |
| `useModel(id)` | `GET /api/models/{id}` | Model detail; id URL-encoded (custom ids contain `/`). |
| `useInfer()` | `POST /api/models/{id}/infer` | mutation → `{run_id}`. |
| `useInferenceResult(runId)` | `GET /api/inference/{id}/result` | polls at 1500ms while `status==="running"`. |
| `useTrainTrack(project?)` | `GET /api/model-tracks/train` | `{runs: TrainRun[]}`; honest-empty (`{runs:[]}`) on `!ok`. |
| `useAdaptTrack(project?)` | `GET /api/model-tracks/adapt` | `{pendingCount, pairs}`; honest-empty on `!ok`. |
| `useOptimiseTrack(project?)` | `GET /api/model-tracks/optimise` | `OptimiseData` **or `undefined`** when `active:false`/no rounds → the panel shows its empty state. |
| `useAdaptToggle()` | `POST /adapt/{pairId}/toggle` | mutation `{pairId, on?, project?}`; invalidates the adapt read. |
| `useAdaptRetrain()` | `POST /adapt/retrain` | mutation `{project?}`; invalidates adapt **and** train reads. |

### 2.4 `frontend/server/routes.ts` — Node proxy + run registration

- `_dlProxyHandler` — the shared DL-surface proxy (unchanged); now also fronts
  `app.all("/api/model-tracks/*", …)`.
- `_adaptRetrainHandler` — dedicated handler for `POST /api/model-tracks/adapt/retrain`:
  1. proxies to Galaxy exactly like `_dlProxyHandler`, capturing the JSON;
  2. **best-effort** registers a first-class run via `storage.createExecutionRun`
     tagged `workflow_type:"training"` / `executionEngine:"pipeline"`, then sets
     the terminal status via `updateExecutionRunStatus` (Galaxy job
     `succeeded→completed`, `failed/cancelled→failed`, else running/queued) and,
     when completed, `updateExecutionRunProgress(run.id, 1, 0, …)`;
  3. returns the Galaxy JSON **plus `runId`** for deep-linking.
  A registration failure only logs — it never alters the API response.
  Registered **before** the generic `/api/model-tracks/*` route so it intercepts.

---

## 3. Backend — function-level reference (`models_inference.py`)

The module is a **thin presentation/dispatch layer** over capability that
already exists (the same discipline as the inference layer it extends). All
reads are best-effort with honest-empty fallback; **no metric/score/round is
ever fabricated.**

### 3.1 Track reads

| Function | Route | Maps |
|---|---|---|
| `train_track(project=None)` | `GET /api/model-tracks/train` | `_adaptation_training_runs(project)` (real `regulatory_training_jobs`, incl. retrains, live status, most-recent-first) **then** registered custom scorers per campaign. |
| `_adaptation_training_runs(project)` | — | `rj.list_for_user(project or "models-track")`; maps `TrainingJob` → track row; status via `_JOB_STATUS_MAP`. Best-effort `[]`. |
| `adapt_track(project=None)` | `GET /api/model-tracks/adapt` | `_read_dpo_pairs(project)` (customer before→after DPO JSONL) with each pair's `on` = `pair_id not in _load_disabled_pairs()`. `pendingCount` = active pairs. |
| `optimise_track(project=None)` | `GET /api/model-tracks/optimise` | first campaign with a proposal round via `_optimise_for_campaign`; else `{active: False}`. |
| `_optimise_for_campaign(campaign_id)` | — | latest `AutoProposal` round → DMTA loop. `ad_statuses` (`in_domain`/`outside_domain`, parallel to `proposed_smiles`) → accepted / `rejected · out of applicability domain`. |

### 3.2 Optimise shaping helpers (pure — unit-tested)

| Function | Contract |
|---|---|
| `_resolve_score_list(scores, smiles)` | Normalize `scores` (either `{objective:[…]}` or `{smiles:score}`) to a per-compound list of `len(smiles)`, `None` where unknown. **Never fabricates.** |
| `_ci_at(cis, smi, idx)` | Pull a `(lo,hi)` from `confidence_intervals` — dict-by-smiles, dict with parallel `lo`/`hi` arrays, or list-of-pairs. `None` when absent. |
| `_confidence_from_ci(ci)` | CI width → band: `≤0.1 high`, `≤0.3 medium`, else `low`; `medium` when unknown. |
| `_JOB_STATUS_MAP` | worker vocab → dashboard vocab (`succeeded→completed`, `cancelled→failed`, …). |
| `_fmt_num(v)` | `"%.3g"` or `—`. |
| `_fmt_ts(ts)` | unix ts (or ISO string) → `YYYY-MM-DD`; `—` when falsy. |

### 3.3 Adapt mutations

| Function | Route | Behaviour |
|---|---|---|
| `TogglePairRequest` (pydantic) | body of toggle | `on: Optional[bool]` — explicit target; omitted → flip. Added to the module's pydantic-rebuild loop so it validates on both v1 and v2. |
| `_disabled_pairs_path()` | — | `disabled_pairs.jsonl` beside the DPO store (or `BIOMATE_DPO_DIR`). |
| `_load_disabled_pairs()` | — | Coalesce the append-only override log → current disabled `set`; last write per `row_id` wins. |
| `_append_disabled_override(row_id, disabled)` | — | Append one `{row_id, disabled, at}` line under `_disabled_lock`. |
| `toggle_adapt_pair(pair_id, body)` | `POST /adapt/{id}/toggle` | Flip logic: **`want_on = currently_disabled`** when no explicit target (was-off→on, was-on→off); persists `disabled=not want_on`. Never mutates the DPO store. |
| `retrain_adapt(project=None)` | `POST /adapt/retrain` | `rj.submit(user_id, org_id)` (default `prompt_rules` mode, cheap/no-GPU) → advances **one `worker.tick(max_jobs=5)`** so the job reaches a terminal state and writes a real artefact → returns `{job_id, status, edit_pair_count, message}`. GPU modes are not started here (the worker refuses them without a harness witness). |

---

## 4. Data stores this phase reads/writes (all pre-existing except the sidecar)

| Store | Path | Written by | Read by |
|---|---|---|---|
| Custom-model registrations | per-campaign SQLite in `BIOMATE_CAMPAIGN_DB_DIR` | drug-discovery campaign registry | `train_track`, registry, model detail |
| DPO edit pairs | `data/regulatory_training/dpo/customer_pairs.jsonl` | `regulatory_pair_recorder.record_pair` | `adapt_track` |
| **Disabled-pairs override (new)** | `data/regulatory_training/dpo/disabled_pairs.jsonl` | `_append_disabled_override` | `_load_disabled_pairs` → `adapt_track` |
| Training jobs | `data/regulatory_training/training_jobs.jsonl` | `regulatory_training_jobs.submit` / `mark_status` | `_adaptation_training_runs` |
| Optimizer proposals | campaign DB `auto_proposals` table | `auto_retrain.save_auto_proposal` | `_optimise_for_campaign` |
| Runs dashboard | Postgres `execution_runs` (+ in-memory) | `storage.createExecutionRun` | `/dashboard` |
| Org-rule artefact | `data/regulatory_training/org_rules/{org}.yaml` | `regulatory_training_worker._do_prompt_rules` | `ind_assembly._build_rag_context` at next inference |

The **only new store** is the append-only `disabled_pairs.jsonl` sidecar — chosen
because the DPO store is append-only and read by the training worker, so a
learned pair's on/off state must live in a separate override the compiler can
consult, never by mutating the DPO rows.

---

## 5. Honesty contract (enforced end-to-end)

- Reads return **honest-empty** when their store is missing/empty: `{runs:[]}`,
  `{pairs:[]}`, `{active:false}` → the UI renders its empty state.
- **No fabricated numbers**: `_resolve_score_list`/`_ci_at` return `None` where a
  value is unknown; `_fmt_num`/`_fmt_ts` return `—`; the interface signature is a
  call-shape descriptor, not a per-model claim.
- Safety-gate rejections (out-of-applicability-domain proposals) are **shown with
  their reason**, never dropped.
- Run registration on retrain is **tagged training**, never faked as a Nextflow
  subprocess.

---

## 6. Bugs found & corrected during this documentation pass

1. **Optimise verdict math (caught during implementation review):** the initial
   `_optimise_for_campaign` assumed `scores`/`ad_statuses` were dicts keyed by
   SMILES; the real `AutoProposal` uses **parallel lists** (`proposed_smiles` +
   `ad_statuses`). Fixed to index positionally via `_resolve_score_list`/`_ci_at`;
   locked by `test_resolve_score_list_shapes` / `test_ci_at_shapes`.
2. **Adapt toggle flip inversion (caught by round-trip smoke test):** the first
   flip logic (`want_on = not currently_disabled`) left an enabled pair enabled.
   Corrected to `want_on = currently_disabled`; locked by
   `test_adapt_toggle_roundtrip`.
3. **Inaccurate comment on `retrain_adapt` (caught while writing §3):** an early
   comment claimed the Train track "reads the same jobs store", when it only read
   custom registrations. Fixed by actually surfacing `regulatory_training_jobs`
   in `train_track` (`_adaptation_training_runs`) so the claim is now true.

No new bugs were found in the frontend during this pass; the 19 vitest cases and
19 backend shape cases pass (§8).

---

## 7. Known remaining gaps (honest, out of this phase's scope)

- **`WetLabRound` (spec §3.7) — the full wet-lab loop.** This phase built the
  Optimise **proposal table** (the surrogate-facing half), but the reference's
  returns/routes/mapping/refit tabs (measured vs predicted, plate-map ingest,
  censored values, refit) are **not** built. This is the flagship differentiator
  the gap inventory called out; it remains ~0% and should be the next Models
  increment.
- **GPU LoRA on Batch (`post_train_lora`).** The infra exists (`submit_batch_job`
  with GPU support, `biomate-gpu-spot-queue`, the `trl-training` ECR image,
  `trl_trainer._train_dpo`, EventBridge+CompletionPoller). The **missing piece**
  is a wire from Batch completion → `TrainingJob.mark_status`. `retrain_adapt`
  therefore only runs the cheap `prompt_rules` mode; GPU mode stays gated. A
  ~140-LOC follow-up (Nextflow-on-Batch wrapper + completion callback) is the
  clean path — deliberately not built here.
- **Registry side-panels + "Plug in a model" (§3.4/§3.5)** and the **linked
  pLDDT↔3D selection** in the viewers remain from the gap inventory; untouched by
  this phase.

---

## 8. Verification status (as of this doc)

- **Frontend:** `tsc --noEmit -p .` clean; `vitest run components/models` **19/19
  green** (objects-not-strings, all three tracks empty+populated+callbacks,
  safety-gate rejection, self-fetch via hooks, default-mutation POST paths).
- **Backend:** `models_inference.py` `py_compile` OK on Python 3.9; isolated
  import registers all routes; `test_models_inference_shape.py` **19/19** (was 12;
  +7 this phase covering the track helpers + toggle round-trip). End-to-end smoke
  (seed DPO pairs → `retrain_adapt` → `succeeded` with a real org-rule YAML →
  appears as a completed adaptation run in `train_track`) verified in isolation.
- **Not yet run:** dev-stack E2E (real Galaxy + Postgres) — see the test plan
  `docs/20260907_MODELS_MODULE_TEST_PLAN.md` §"Live dev E2E".
