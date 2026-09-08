# Models Module — Phase Upgrade: Team Test Plan

**Date:** 2026-09-07
**Covers:** PR #212 (`feat/models-real-tracks`) — 5 real tracks, Model Object
objects-not-strings, live track reads, persisted Adapt mutations, retrain →
first-class run.
**Companion:** `docs/20260907_MODELS_MODULE_PHASE_UPGRADE_ARCHITECTURE.md`
(function-level reference; read it first).

**How to read this plan:** §1 is the automated suite the author already runs
(green today). §2 is the manual/live-dev checklist for the team before sync.
§3 is the E2E harness spec (consolidated per CLAUDE.md e2e discipline). §4 is the
coverage map (what is covered where, so we don't re-implement). §5 is the risk
register. Every UI assertion cites a real `data-testid`.

---

## 0. Test pyramid & where each layer runs

| Layer | Where | Command | Status |
|---|---|---|---|
| FE unit/integration | `frontend/client/src/components/models/models.test.tsx` | `npx vitest run components/models` | ✅ 19/19 |
| FE type check | whole app | `npx tsc --noEmit -p .` | ✅ clean |
| BE contract/shape | `backend/test/unit/webapps/api/test_models_inference_shape.py` | `PYTHONPATH=lib python3.9 -m pytest … --noconftest` | ✅ 19/19 |
| BE module load (3.9) | `models_inference.py` | `python3.9 -m py_compile` / isolated import | ✅ |
| Live dev E2E | dev-public.biomate.ai | new harness `scripts/e2e_models_tracks.sh` (§3) | ⬜ to run before merge |

---

## 1. Automated suite (author-run; must stay green)

### 1.1 Frontend — `npx vitest run components/models` (19 cases)

Groups and what each locks:

- **ModelsPanel** — all 5 tracks render (`models-track-0..4`); Registry lists
  catalog rows and a row opens the Model Object.
- **ModelObject** — the evidence gate triple (measured·threshold·verdict);
  lineage/consumers/interface/versions tabs; **objects-not-strings**: lineage
  links fire `onOpenData`/`onOpenRun`, consumer "open →" fires `onOpenConsumer`,
  header "Use in a run"/"Supersede" fire their callbacks, interface signature
  present.
- **Train track** — loop + families always render; honest empty runs state with
  no data; populated runs with status/gate + watch-live/open-experiment; click
  opens the model object.
- **Adapt track** — level ladder always; honest empty learned state; populated
  before→after pairs; toggle fires the callback; **with no `onAdaptToggle` prop,
  toggling POSTs the persisted override endpoint**; **with no `onAdaptRetrain`
  prop, Re-train POSTs the retrain endpoint**.
- **Optimise track** — honest empty when no data; populated DMTA loop + surrogate
  links + proposal table with a **safety-gate rejection shown**.
- **Self-fetch** — training runs fetched from `/api/model-tracks/train` with no
  props; DMTA loop fetched from `/api/model-tracks/optimise`.
- **InferenceResultView / RunPretrained** — structure/genomic/chemical routing +
  stub badge (pre-existing).

Pass criterion: **19 passed, 0 failed**. Any red here blocks the PR.

### 1.2 Backend — `test_models_inference_shape.py` (19 cases)

Run (the repo conftest pulls heavy pydantic; run standalone):
```
cd backend && PYTHONPATH=lib python3.9 -m pytest \
  test/unit/webapps/api/test_models_inference_shape.py -q --noconftest
```
Locks: catalog row shape; BioNeMo catalog; evidence-class routing; stub shapes
(no fabricated scores); interface-kind mapping; custom-id parse; pLDDT-from-PDB;
**Optimise helpers** (`_fmt_num`/`_fmt_ts`, `_confidence_from_ci`,
`_resolve_score_list`, `_ci_at`, `_JOB_STATUS_MAP`); **Adapt toggle round-trip**
(`test_adapt_toggle_roundtrip`, `test_toggle_requires_pair_id`); run-registry
shared store; self-host dispatch not gated on API key.

Pass criterion: **19 passed**.

### 1.3 Backend module-load gate (mandatory before any sync)

```
cd backend && PYTHONPATH=lib python3.9 -m py_compile \
  lib/galaxy/webapps/galaxy/api/models_inference.py
```
Catches PEP-604 / import failures that crash gunicorn (the 2026-06-03 incident).

---

## 2. Manual / live-dev checklist (team, before merge)

Do these on **dev-public.biomate.ai** with the shared fixture
`lifeifei163361@163.com` (CLAUDE.md). One login, one project, reuse the session.

### 2.1 Model Object — objects, not strings
- [ ] Open Registry → click a model row → the Model Object opens (crumb + name +
      family + confidence band).
- [ ] Header shows **"Use in a run"** and **"Supersede"** buttons.
- [ ] **Lineage** tab: dataset / training-run / prior-version render as links when
      present; clicking does not error (fires the callback / navigates).
- [ ] **Used by**: each consumer shows kind · where · how + an "open →".
- [ ] **Interface**: the signature line renders (e.g. `POST /infer {inputs} -> result`).
- [ ] **Versions**: current version marked; other versions show a "compare" link.
- [ ] No visible **"undefined"** anywhere; absent values render `—`, not blank.

### 2.2 Train track
- [ ] Loop diagram (Dataset → Train → Quality gate → Register) + families grid always show.
- [ ] With no model work: **honest empty** ("This project hasn't trained…").
- [ ] After a retrain (see 2.4): an **adaptation run** appears at the top with a
      status pill (completed/running) and metric "N edit pairs".

### 2.3 Adapt track
- [ ] Level ladder (prompt rule → few-shot index → trained adapter) shows.
- [ ] With no pairs: **honest empty** ("Nothing learned yet…").
- [ ] With pairs: each shows **before (red strikethrough) → after (green)** + a toggle.
- [ ] Toggling a pair **persists** — reload the page, the pair stays in the toggled
      state (this exercises `disabled_pairs.jsonl`).
- [ ] "Re-train on my edits" shows the pending count and triggers a retrain.

### 2.4 Retrain → first-class run (the cross-surface check)
- [ ] Click **"Re-train on my edits"**.
- [ ] The response completes (status `completed` for the cheap prompt_rules mode).
- [ ] Navigate to **/dashboard (Runs)** → a run named **"Adaptation retrain"** appears,
      tagged training, status **completed** (or running→completed).
- [ ] The Train track now lists that adaptation run too.
- [ ] **Negative:** it is NOT presented as a Nextflow pipeline (no phase/step
      graph faked); it is honestly a training run.

### 2.5 Optimise track
- [ ] With no optimizer round: **honest empty**.
- [ ] With a campaign that has proposals: DMTA loop header (running/round),
      surrogate model link(s), rounds list, proposal table with id/score/
      confidence/verdict.
- [ ] Any **out-of-applicability-domain** proposal is shown **red** with its
      reason (not dropped).
- [ ] Clicking a surrogate opens its Model Object.

### 2.6 Registry + Run-a-pre-trained-model (regression)
- [ ] Registry lists the live catalog; count badge matches row count.
- [ ] Run-a-pre-trained-model: pick a domain, submit, poll, viewer renders (stub
      badge when the NIM is unreachable — expected on dev without NVIDIA key).

---

## 3. Live-dev E2E harness (to author: `scripts/e2e_models_tracks.sh`)

Follows the CLAUDE.md e2e discipline: **one login, one project, 1–2 consolidated
flows, 90s LLM timeouts, coverage notes**. Uses the shared fixture and the
`x-e2e-test-token` bypass on dev.

**Flow A (sequential journey):**
1. Login once (cache JWT); create one project.
2. `GET /api/model-tracks/train?project=<p>` → 200, `{runs:[...]}` (array).
3. `GET /api/model-tracks/adapt?project=<p>` → 200, `{pendingCount, pairs}`.
4. `GET /api/model-tracks/optimise?project=<p>` → 200, `{active:false}` OR a loop.
5. `POST /api/model-tracks/adapt/retrain?project=<p>` → 200, `{job_id, status, runId}`.
   Assert `status ∈ {completed, running, queued}` and `runId` present.
6. `GET /api/execution-runs` (or the dashboard list endpoint) → the `runId` from
   step 5 is present with `workflowName:"Adaptation retrain"`.
7. If a pair exists: `POST /api/model-tracks/adapt/<pairId>/toggle` → 200,
   `{id, on}`; re-`GET /adapt` → that pair's `on` flipped (persistence proof).

**Flow B (cheap auth-gate probe):**
- `GET /api/model-tracks/train` with no auth cookie → 401.
- `GET /api/models/does-not-exist` → 404 (not 500).

**Timeouts:** 90s on the retrain POST (it runs the worker tick synchronously; the
prompt_rules compile is seconds, but leave headroom). 30s on reads.

**Coverage notes (do NOT re-implement here):** the objects-not-strings rendering,
the empty states, the toggle-fires-callback, and the safety-gate rejection
display are all covered by `models.test.tsx` (§1.1). The Optimise math and toggle
round-trip are covered by `test_models_inference_shape.py` (§1.2). The harness
only adds the **live wiring** proof (proxy → Galaxy → real store; retrain → run
row in Postgres).

---

## 4. Coverage map (what proves what — avoid duplication)

| Requirement | Proven by |
|---|---|
| 5 tracks render; Registry opens object | `models.test.tsx` ModelsPanel |
| Model Object objects-not-strings (links, signature, header, compare) | `models.test.tsx` ModelObject |
| Train/Adapt/Optimise empty + populated + callbacks | `models.test.tsx` per-track describes |
| Safety-gate rejection shown | `models.test.tsx` Optimise |
| Self-fetch defaults from hooks | `models.test.tsx` self-fetch describe |
| Default toggle/retrain POST the endpoints | `models.test.tsx` Adapt (no-prop cases) |
| Optimise score/CI/status shaping | `test_models_inference_shape.py` helpers |
| Adapt toggle persistence & flip logic | `test_models_inference_shape.py` toggle round-trip |
| Stub shapes / evidence routing (regression) | `test_models_inference_shape.py` |
| Module loads on 3.9 (no crash) | `py_compile` gate |
| Live proxy → Galaxy → real store; retrain→run row | `e2e_models_tracks.sh` (§3) |
| Cross-surface (Runs dashboard shows retrain) | §2.4 manual + Flow A step 6 |

---

## 5. Risk register (what to watch)

| # | Risk | Detection | Mitigation |
|---|---|---|---|
| R1 | Route collision: `/api/model-tracks/adapt/retrain` swallowed by the greedy `/api/models/{id:path}` on Galaxy, or by the generic Node proxy | Retrain returns a model-detail 404, or the run is never registered | Distinct `/api/model-tracks/*` prefix (Galaxy) + specific-before-wildcard Node registration; assert in Flow A step 5/6 |
| R2 | Retrain leaves the job queued (worker tick didn't run) | `status:"queued"` never advancing; no org-rule YAML | `retrain_adapt` runs `worker.tick` inline; assert `status` in Flow A step 5 |
| R3 | Toggle doesn't persist (sidecar not written / wrong flip) | Reload loses the toggle; flip is a no-op | `test_adapt_toggle_roundtrip` + manual 2.3 reload check |
| R4 | Optimise proposal table fabricates scores when the store shape differs | Numbers appear where the store has none | `_resolve_score_list`/`_ci_at` return `None`; `test_resolve_score_list_shapes` |
| R5 | Run registration failure breaks the retrain API response | Retrain 5xx when Postgres is down | Registration is best-effort (try/catch, logs only); API returns Galaxy JSON regardless — assert retrain still 200 with Postgres unreachable |
| R6 | Module-load failure crashes gunicorn on dev | Galaxy 502 after sync | `py_compile` + isolated import gate before sync (§1.3) |
| R7 | `useOptimiseTrack` returns `{}` instead of `undefined` → panel shows a broken half-loop | Optimise renders header with empty rounds | Hook returns `undefined` unless `Array.isArray(rounds)`; `models.test.tsx` self-fetch |

---

## 6. Exit criteria (before merge → sync to dev)

1. §1.1 vitest 19/19 + §1.2 backend 19/19 + §1.3 py_compile all green.
2. `tsc --noEmit` clean.
3. §3 `e2e_models_tracks.sh` Flow A + B pass on dev.
4. §2 manual checklist walked once on dev with no "undefined" and persisted
   toggle verified across a reload.
5. Known gaps (§7 of the architecture doc: WetLabRound, GPU LoRA) explicitly
   deferred, not silently shipped as "done".
