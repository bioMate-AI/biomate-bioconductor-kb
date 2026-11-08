# Data-Centric Upgrade — Comprehensive E2E Test Plan

**Date:** 2026-09-08
**Branch under test:** `feat/data-centric-upgrade` (via `feat/e2e-comprehensive`)
**Harness:** `scripts/e2e_data_centric.sh`
**Run command:**
```bash
# After feat/data-centric-upgrade merges into integration/next-phase AND syncs to dev:
BIOMATE_URL=https://dev-public.biomate.ai bash scripts/e2e_data_centric.sh
```
Per-run log: `docs/e2e_runs/<TS>_data_centric.log` (gitignored).

---

## 1. Scope — what "data-centric upgrade" adds

The upgrade adds three user-facing surfaces, all proxied through the Node
frontend (`frontend/server/routes.ts`, `optionalAuth`, `_dlProxyHandler`) to
Galaxy FastAPI routers. This harness exercises **all of them** end-to-end over
real HTTP on dev — no mocks (per the CLAUDE.md "NEVER mock" rule).

| Surface | Endpoints | Galaxy backend |
|---|---|---|
| **Models module** | `GET /api/models`, `GET /api/models/{id}`, `POST /api/models/{id}/infer`, `GET /api/inference/{run_id}/result`, `GET /api/model-tracks/{train,adapt,optimise}`, `POST /api/model-tracks/adapt/retrain` | `api/models_inference.py` |
| **Design & Generate** | `POST /api/generate`, `GET /api/generate/{run_id}` | `api/generation.py` |
| **Data surfaces** | `POST /api/perception/profile`, `GET /api/datasets/{ref}/{lineage,consumers,versions}` | `api/perception.py`, `api/datasets_object.py` |
| **Nextflow panel** | `GET /api/nextflow/skip-analysis` | `api/nextflow_executor.py` |

---

## 2. Depth-review findings — why the prior coverage was shallow

The task asked me to review the referenced files first. Findings:

1. **`scripts/e2e_models_tracks.sh` and `scripts/coldstart_executability_guard.py`
   and `docs/20260907_MODELS_MODULE_TEST_PLAN.md` do not exist** on
   `feat/data-centric-upgrade`. They were named in the task but are not on the
   branch — so there was **no pre-existing HTTP-level E2E for the data-centric
   surfaces at all**. That is the deepest gap: the entire new API surface had
   zero live-wired-path coverage.

2. **Existing coverage is real but two layers away from the wire:**
   - `frontend/client/src/components/models/models.test.tsx` (vitest/jsdom) —
     covers React rendering of all five tracks + the react-query hooks, but with
     **mocked `fetch`**. It proves the component renders a given payload; it does
     NOT prove the Node proxy is registered, that Galaxy answers, or that the two
     agree on the contract shape.
   - `backend/test/unit/webapps/api/test_models_inference_shape.py` (pytest) —
     covers the models_inference contract shapes **in-process** (imports the
     module, calls the functions). It does NOT go through the Node proxy, the
     `optionalAuth` middleware, or the Galaxy HTTP router.
   - `generation.py`, `perception.py`, `datasets_object.py`, and the
     `skip-analysis` endpoint have **no dedicated backend unit test** in the tree.

3. **The one thing no existing test can catch** is a break in the wired path:
   an unregistered Node route, a proxy that drops the body/query, a Galaxy router
   not mounted, or a contract drift between the mocked frontend fixture and the
   real backend payload. The most likely regression is someone "hardening" an
   `optionalAuth` route into `requireAuth` — which would 401 the anonymous
   Models/Design panels and no unit test would notice.

4. **The canonical `scripts/e2e_use_cases.sh` is the right shape** (single
   fixture, one login, one project, Flow A journey + Flow B gate probes, P0/P1/P2
   gating, 90 s LLM budgets, coverage notes) but exercises **none** of the
   data-centric surfaces. This harness mirrors its discipline exactly and extends
   it to the new surfaces.

**How this harness is deeper:** it is the only coverage that (a) drives the
real Node→Galaxy path on dev, (b) asserts **contract shape**, not "is JSON"
(e.g. every model row has `id/name/family/version/origin`; a `DataProfile` has
`quality`+`notes[]`; a lineage object has `ref/available/source/producedBy`),
(c) asserts the **honesty contract** (unresolvable ref → `quality:'blocked'` with
a note, never a fabricated leakage number; unevaluated model → verdict string,
never a fake metric; fresh project → honest-empty tracks), and (d) asserts the
**auth posture** (optionalAuth reads must NOT 401, contrasted against
`/api/projects` which must 401).

---

## 3. Assertions (per surface, with priority + coverage map)

Priorities: **P0** = block sync (exit 2); **P1** = warn, release-note (exit 1);
**P2** = advisory. A distinct **exit 3** = "routes not deployed" (preflight).

### Preflight — `route_missing` gate
- `GET /api/models` must return a JSON array. If 404 / not-an-array → abort with
  a "merge + sync first" diagnosis and **exit 3** (distinct from assertion fails).
  *Verified live on dev 2026-09-08: dev returned 404 `API route /api/models not
  found` → harness exited 3 with the diagnosis, as designed.*

### Flow A — authenticated journey (one login, one project)

| ID | Assertion | Prio | covers | defers to |
|---|---|---|---|---|
| A0 | fixture login → JWT; `POST /api/projects` → uuid | P0 | live auth + project create | — |
| A1 | `GET /api/models` is a JSON array; each row has `id+name+family+version+origin` (gated on non-empty; empty = honest) | P0 | proxy→Galaxy catalog list + row contract | ModelsPanel Registry render (models.test.tsx) |
| A2 | `GET /api/models/{id}`: has `identity.name` + `evidence.gate.verdict`; exposes `lineage/consumers/interface/versions`; verdict is a string (honest); unknown id → 404 | P0 (404 P0, verdict-string P1) | detail contract + 404 | ModelObject tab render (models.test.tsx) |
| A3 | `POST /api/models/{id}/infer` → 200(`run_id`) or honest 4xx; `GET /api/inference/{run_id}/result` reaches `completed\|failed`; unknown run → 404 | P0 (unknown-run P1) | full submit→poll wired loop | InferenceResultView routing (models.test.tsx) |
| A4 | `train`→`{runs:[]}`; `adapt`→`{pendingCount:int, pairs:[]}`; `optimise`→`{active:…}`; fresh project ⇒ not active | P0 (not-active P1) | live track reads + honest-empty | track render + toggle (models.test.tsx) |
| A5 | `POST /api/model-tracks/adapt/retrain` → 2xx, not 5xx | P1 | retrain trigger well-formed | re-train button + query invalidation (models.test.tsx) |
| A6 | `POST /api/generate` → `run_id`+`status`; `GET /api/generate/{run_id}` reaches non-running terminal; unknown run → 404 | P1 | de-novo generation submit→poll loop | design-generate UI (component tests) |
| A7 | `POST /api/perception/profile` with unresolvable ref → `quality:'blocked'` + `notes[]`; missing ref → still blocked (not 5xx) | P1 | ingest profiler + honest-degrade | DatasetObject Quality tab (component) |
| A8 | `lineage` has `ref/available/source/producedBy`, unknown ref → `available:false`; `consumers`→`{consumers:[]}` empty for unknown; `versions`→`{versions:[]}` | P0 (consumers-empty P1) | data-object reads + honest-empty | Lineage/Consumers/Versions tabs (component) |
| A9 | `skip-analysis` no param → 400; with path → `{phases:[], count:int}`; each phase (if present) has `id+label+skippable` | P0 (phase-keys P1) | panel skip/dep read + 400 guard | SkipDependency panel (nextflow-workflow-viewer tests) |

### Flow B — optionalAuth posture (no login)

| Assertion | Prio |
|---|---|
| `GET /api/models` no-token → not 401 (200/502/503) | P0 |
| `GET /api/model-tracks/train` no-token → not 401 | P0 |
| `POST /api/perception/profile` no-token → not 401 (200/400/422/502/503) | P0 |
| `GET /api/nextflow/skip-analysis` no-token, no param → 400 (not 401) | P0 |
| `GET /api/projects` no-token → 401 (contrast: real auth gate intact) | P0 |

---

## 4. Coverage map (do-not-duplicate)

| Layer | Owner | This harness re-verifies? |
|---|---|---|
| React render of Models/Design/Datasets panels + react-query hooks | `frontend/client/src/components/models/models.test.tsx` (mocked fetch, jsdom) | No — defers |
| Backend models_inference contract shapes (in-process) | `backend/test/unit/webapps/api/test_models_inference_shape.py` | No — defers |
| Cross-user project ownership (404-not-403), 7-assertion matrix | `frontend/server/project-routes.test.ts` + `scripts/audit_project_framework.sh` | No — defers |
| **Live wired path (Node proxy → Galaxy) + HTTP auth posture on dev** | **this harness** | **Yes — sole owner** |

---

## 5. Discipline compliance (CLAUDE.md)

- Single canonical fixture `lifeifei163361@163.com`; **one** login, **one**
  project (trap-cleaned on EXIT). Never calls `/api/auth/register`.
- Flow A = sequential journey; Flow B = cheap auth-gate probes.
- 90 s timeouts on infer / generate / retrain (LLM/dispatch paths).
- No mocks — real backend over HTTPS on dev.
- P0/P1/P2 gating with sync-blocking exit codes; exit 3 for not-deployed.
- Contract-shape + honesty-contract assertions, not "is JSON".

## 6. Open items / next steps

- The harness is **not yet runnable green** — the data-centric routes 404 on dev
  until `feat/data-centric-upgrade` merges into `integration/next-phase` and
  `scripts/sync_to_dev.sh` runs. This is by design (exit 3, verified).
- After merge+sync, run the harness; capture the run log; if any P0 fails, do NOT
  sync further and root-cause per the CLAUDE.md discipline.
- If the live catalog is empty on dev (no BioNeMo client fns exposed, no custom
  campaigns), A2/A3 self-skip with an honest warning — this is expected and does
  not fail the run. To force A2/A3 coverage, ensure at least one BioNeMo model is
  registered in `bionemo_client._FUNCTIONS` on the dev backend.
