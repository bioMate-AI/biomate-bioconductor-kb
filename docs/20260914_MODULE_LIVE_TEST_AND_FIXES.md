# Session — Phase 1 completion, module live-testing, and root-cause fixes

**Date:** 2026-09-14
**Branch:** `integration/dev-test`
**Scope:** finish Phase 1 of
[`20260912_V2_GAP_REBASE_AFTER_SIMPLIFICATION.md`](20260912_V2_GAP_REBASE_AFTER_SIMPLIFICATION.md),
then live-test the four scientific entry-point modules and fix what the testing
surfaced.

## 1. Phase 1 (execution & object coherence) — complete

All four P0s implemented, deployed to dev, verified, and audited (one GO doc each):

| Item | Audit | Summary |
|---|---|---|
| 1A Authenticated output truth | `20260913_PHASE1A_*` | `output-access.ts` + auth on 6 IDOR routes; 401/404 verified |
| 1B Real inputs bound (provenance) | `20260913_PHASE1B_*` | `inputBindings` on runs + migration 0021 |
| 1C Comparison compatibility | `20260913_PHASE1C_*` | `input-compatibility.ts` + `/files/compatibility` endpoint |
| 1D Honest blocked states | `20260913_PHASE1D_*` | generation-failed + unresolved-input execute gates |

**Client wiring (`57bdbacd7`)** — threaded `datasetReferenceUnresolvedIds` from
the chat-stream payload → `message.metadata` → `onExecute` → `executeWorkflow`
so 1D's `inputs_unresolved` gate engages for the chat path. The compare-files
UI consumer for 1C was deferred (no such pre-launch UI exists; building one
would be speculative).

Infra: sync-script silent-fail hardening (dogfooded on every deploy this
session — "verified fresh container" checks).

## 2. Module live-tests (dev) — evidence-based

Each module was exercised against https://dev-public.biomate.ai (fixture
`lifeifei163361@163.com`). Read-only maps were produced first, then live runs.

| Module | Flow | Real output | Finding |
|---|---|---|---|
| **Models** | ✅ catalogue + submit/poll | ✅ after fix | Initially read as "stub only", but that was testing esmfold (deprecated). Root cause was **version pinning** (`…/versions/{ver}` 404s when NVIDIA rotates versions), not the key — fixed (§7). boltz2 now returns a real prediction. |
| **Search & evidence** | ✅ cited answer | ✅ | Two bugs found + fixed (§3). |
| **Design & generate** | ✅ submit/poll | ✅ after fix | Was **dead → hanging → working** (§4). |
| **Data analysis** | — | — | Covered by Phase-1 1A–1D. |

Model-status labeling (validated-predictive / project-adapted / heuristic) was
**dropped per product decision** — not built.

## 3. Search & evidence fixes (`a0b93dfa2`) — `research_agent.py`

Live test ("IL-23 → psoriasis") exposed two defects:
1. **Citation mismatch** — the synthesis prompt numbers the FULL retrieved pool
   [1..N] (≤40) and the model cites by those numbers, but only the first
   `max_citations` (=5) were returned → inline `[12]/[16]/[23]` pointed at
   dropped papers and uncited/irrelevant papers were surfaced.
2. **No evidence boundary** — answers lacked any caveat/scope statement.

Fixes in `_synthesize_response`:
- `_ground_citations()` — keep exactly the papers the answer's `[N]` markers use,
  renumber them contiguously in both the text and the returned list; fall back
  to top-N when there are no numeric markers.
- `_ensure_evidence_boundary()` — guarantee a one-line boundary/caveat (appended
  from citation-count + confidence only when the model didn't already write one);
  prompt also instructs the model to end with `**Evidence boundary:**` and to
  cite only genuinely-supporting papers.

Verified on dev: markers now `[1..8]` all mapping to 8 relevant citations; answer
ends with a model-authored Evidence boundary. Pure helpers unit-checked on py3.9.

## 4. Design & generate fixes — two layered RDKit root causes

The module was **completely dead** on dev (`no candidates: rdkit_unavailable`).

**Root cause 1 — RDKit missing from the image (`3c0d0ba56`).** It is not in
`backend/requirements.txt` (Galaxy's pinned deps); the container had only a
broken partial `rdkit/__init__.py`. `generation.py` / `generators.py` import it
in-process (`Chem/QED/BRICS/Descriptors/Crippen/FilterCatalog`). Added an
explicit `pip install` to `backend/Dockerfile`.

**Root cause 2 — segfault under numpy 2 (`21bab40b2`).** rdkit 2023.9.6 is built
for numpy 1.x; the image ships numpy 2.0.2. Under numpy 2 that rdkit **segfaults**
(`exit 139`) in `rdkit.ML.InfoTheory` when the generate path exercises rdkit +
numpy together — which is exactly why runs sat at `running` forever (the worker
thread crashed/hung, not minutes of GP math). Pinned **rdkit 2024.3.5** (first
series with numpy-2 support + a py3.9 wheel).

**Diagnosis method (no speculative expensive runs):** an in-process perf probe
(bounded library sizes) showed BRICS 0.15s + GP fit 0.03s + propose ~5.4s — **no
multi-minute algorithmic cost**; the fixed 2023.9.6 build crashed the probe
(exit 139), the 2024.3.5 build ran clean.

**Result:** live `POST /api/generate` now **completes in ~10s** with a real,
scored, verdict-labeled candidate (`BM-0001, QED 1.00`, pareto=1) instead of
hanging.

**Root cause 3 — tiny virtual library (`d0d716654`).** Even with the ABI fixed,
the generator returned ~1 molecule for any seed, so the "candidate list" had one
item. `BRICS.BRICSBuild` only joins fragments whose dummy atoms carry compatible
BRICS bond-type labels (`[16*]`, `[3*]`, …), but the code called
`BRICSBuild([seed_mol])` on the intact molecule (no dummies) and paired seed
fragments with a generically-dummied (`[*]`) medchem set — neither assembles.
Fix: `BRICSDecompose` the seed (→ properly-labelled fragments) and recombine the
whole pool in one `BRICSBuild` pass (sanitize + validity + dedup, capped).
Verified on dev (imatinib, count=15): **n_generated=200 (was 1), 15 distinct
ranked analogues with correct verdicts + pareto**. The scoring/verdict/pareto
pipeline was already correct — it just had nothing to rank.

**Deploy note:** gunicorn runs `--preload`, so `HUP` does not re-import the app
— a module-level flag like `_RDKIT_AVAILABLE` (and a freshly-installed package)
requires a full Galaxy restart to take effect. Dev was hot-patched (pip install
+ restart); the Dockerfile pins make it durable on the next image rebuild.

## 5. Open items (not addressed this session)

- **`propose` ~5.4s fixed cost** — GP hyperparameter restarts over 2048-bit
  Morgan fingerprints per objective. Acceptable; tunable (fewer restarts / lower
  nBits) later.
- **True scaffold-hopping needs an external building-block set** — the library
  is now full (200 from the seed's own labelled fragments, `d0d716654`), but
  introducing *novel* substructures beyond the seed's pieces needs a curated
  BRICS-labelled fragment library. Enhancement, not a bug.
- ~~**`gen_` runs lack an orphan-finalizer**~~ — FIXED (`4733a689d`): a lazy
  on-read finalizer in `get_generation` marks a run failed if it has been
  `running` past `_RUN_STALE_SECONDS` (300s). Verified on dev against a real
  orphaned run.
- **Search "Make instruction" exit** — disabled stub; needs a backend endpoint
  (`POST /api/memory/projects/:id/instructions`).
- ~~**Models real predictions blocked by NVCF**~~ — FIXED (`da212b231`): the key
  was fine; the client pinned stale NVCF *versions*. Now invokes by function id
  (latest active version); evo2_7b id refreshed; deprecated ESMFold dropped from
  the hosted catalogue. boltz2 returns a real prediction on dev. Minor follow-up:
  boltz2's result mapping populated a single `plddt` value (viewer expects
  per-residue) — a result-shape refinement, separate from "does it predict".
- **Durable-vs-dev drift** — backend Dockerfile changes reach dev only on an
  image rebuild; dev is currently hot-patched to match.

## 6. Commits this session (pushed)

`57bdbacd7` client wiring · `a0b93dfa2` search grounding+boundary ·
`3c0d0ba56` rdkit install · `21bab40b2` rdkit numpy-2 pin · `d0d716654` BRICS
virtual-library fix · `4733a689d` gen orphan-finalizer · `da212b231` BioNeMo
version-pinning fix · plus the four Phase-1 audit docs (`20260913_PHASE1A..1D`).
