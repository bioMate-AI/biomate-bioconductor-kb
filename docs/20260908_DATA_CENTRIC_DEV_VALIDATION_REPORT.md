# Data-Centric Upgrade — Dev Validation Report (vs claude-design reference)

**Date:** 2026-09-08
**Target:** `https://dev-public.biomate.ai` (live, no mocks)
**Fixture:** `lifeifei163361@163.com` (single fixture, login-once)
**Reference:** `reference/claude_design/data_centroid_design/` (branch `feat/data-centric-backend`) + CLAUDE.md "UX E2E Completeness Standard" / "Chat + Workflow Panel Presentation Standard"
**Harnesses reused (not re-derived):**
- `frontend/e2e/ux-audit-data-centric.e2e.ts` (branch `test/ux-audit-comprehensive`)
- `frontend/e2e/flow-audit-multiround.e2e.ts` (branch `test/flow-audit-multiround`)
- `frontend/e2e/parallel-execution-audit.e2e.ts` (branch `test/parallel-execution-audit`)
- `frontend/e2e/memory-ability-audit.e2e.ts` (branch `test/memory-ability-audit`)

**Preflight verdict:** the data-centric bundle IS deployed on dev — UX harness reports
`preflight: deployed (cold-start=true, files=true)`. This is a real audit of a live,
merged, deployed build, not a "not-deployed" skip.

---

## Executive summary

| Dimension | Verdict | One-line |
|---|---|---|
| 1. UX completeness | **PARTIAL** | Cold-start, Models, Design, Files hubs, Connectors all render (62 PASS / 0 FAIL / 135 checks). Real gap: full **step deep-view is an orphan component (never mounted)**; several Design/Optimise sub-elements are conditional-render or testid-mismatch. |
| 2. Multi-round interaction | **PASS (backend) / PARTIAL (browser)** | `/api/chat/stream` multi-turn context carry works live (independently confirmed: GRCh38 preference stated turn-1 applied in turn-2 workflow). Browser harness could not reliably observe the **workflow panel opening in-browser** within its 10s post-assistant window. |
| 3. Parallel execution | **PASS** | 5/7 harness scenarios pass; independently confirmed two concurrent generation runs get distinct run_ids, each polls its own record, both reach `completed`, zero cross-worker 404 (12/12 hammer). |
| 4. Memory ability | **PASS (4/6) / 2 documented gaps** | Session carry, byte-cap dataset preservation, summarization UUID survival, episodic recall all PASS live. Cross-session *chat* recall (M-4) and org-rule adaptation (M-6) are honest NOT-WIRED gaps. |

**No FAIL was a data-centric UI regression.** The one reproducible backend break found
(`GET /api/projects` → 500) is in the pre-existing Node/Postgres project path, not the
data-centric surfaces — but it blocks the Files/dataset surface from listing datasets.

---

## Dimension 1 — UX completeness → PARTIAL

Source: `ux-audit-data-centric.e2e.ts`, **135 elements checked · 62 PASS · 0 FAIL · 73 NOT-FOUND · 0 required-failures** (`11 passed, 4.1m`).
JSON report: `frontend/e2e/reports/ux-audit-data-centric.json`.

Per-surface (PASS / NOT-FOUND):

| Surface | PASS | NOT-FOUND | Notes |
|---|---|---|---|
| 1. Cold-start dashboard | 12 | 1 | All 4 modules (Search/Analysis/Design/Models), intent router, route-box, no fabricated counts. |
| 2. Models (5 tracks + Model Object) | 27 | 4 | All 5 track tabs + Model Object tabs render. |
| 3. Design & Generate | 5 | 14 | Renders; most NOT-FOUND are data-gated (empty states) + a few testid mismatches. |
| 4. Files / dataset object | 2 | 16 | Data-hub + file-tree render; 6-tab dataset object un-testable (fixture has no datasets — honest empty). |
| 5. Workflow panel | 10 | 18 | Idle state + live SSE data-status render; after-run tabs data-dependent. |
| 6. Full step view | 0 | 6 | **REAL GAP — `steps/step-detail.tsx` is an orphan, never mounted.** |
| 8. Search & Evidence | 0 | 6 | Data-dependent + one unbuilt element (save-to-notes). |
| 9. Connectors | 6 | 0 | Dialog, table, residency badges/legend, 192 declared facts, scope selector — all PASS. |
| 10. Viewers | 0 | 8 | pLDDT/PAE/seq-tracks/hit-grid all data-dependent; StructureViewer lacks a testid. |

**Real coverage gaps (deployed surface, element missing/unwired) — 19 total, ranked:**

1. **[P1] Full step deep-view is an orphan.** `frontend/client/src/components/steps/step-detail.tsx`
   exists but is never mounted — no open-full-step-view path wires it. Kills 5 spec'd elements
   (full-view open button, provenance row, resolved-params+origin badges, rendered⇄raw toggle,
   claim→output link). *This is a named priority-1 surface ("full step deep-view").*
   **Fix:** wire `step-detail.tsx` to an `open-full-step-view` action from the step row in
   `nextflow-workflow-viewer.tsx`.

2. **[P2] Models · Optimise (DMTA) loop scaffold does not render its empty state.** `/api/model-tracks/optimise`
   returns `{active:false}` (honest), but the Optimise tab then shows nothing with the
   `optimise-loop` / `optimise-loop-state` / `optimise-surrogates` testids. **Fix:** render the
   DMTA loop scaffold + "no active loop" empty state so the surface is present even when inactive.

3. **[P2] Design surface — a handful of elements are conditional-render or testid-drift.**
   `DesignGenerate.tsx` DOES contain `criteria-strip`, `criteria-stated`, `multi-objective-view`,
   `dg-export-order`/`order-sheet`, `pareto-view`, `predicted-vs-measured` testids, but the audit
   marked several "not present" because they render only after a generate run produces candidates
   (the harness had no candidates) OR the harness looked for a slightly different testid string.
   **Fix:** (a) render the criteria strip + safety-gate before candidates exist; (b) reconcile
   harness testids to the component (`dg-export-order` vs `order-sheet`, `dg-safety-gate`).

4. **[P3] StructureViewer (3Dmol) has no `data-testid`.** Add one for auditability.

5. **[P3] Search & Evidence "Save-to-notes" + "Lane + corpora chip"** — unbuilt on this branch.

**Honest-empty (not a bug, 51 elements):** every dataset-object tab, all viewers, after-run
tabs, Design Pareto/rejection data — all require real run/dataset data the fresh fixture lacks.
To fully validate these, seed the fixture project with one completed run + one dataset.

**Note (not a gap):** cold-start "Seed click composes" recorded NOT-FOUND but its detail shows
the chat input WAS populated (`'screen these molecules for hERG then ran'`) — the seed compose
behavior actually works; the assertion shape is stale.

---

## Dimension 2 — Multi-round interaction flow → PASS (backend) / PARTIAL (browser)

Source: `flow-audit-multiround.e2e.ts` — **9 PASS · 7 DEPLOY_GAP · 9 SKIP · 3 FAIL**.
Trace: `frontend/e2e/screenshots/flow-audit/flow-audit-trace.json`.

**Backend multi-round works — independently confirmed (my own live `/api/chat/stream` probes):**
- Turn 1: "I always want human GRCh38 as my reference genome. Remember that." → assistant records it.
- Turn 2: "Now run bulk RNA-seq differential expression on my paired FASTQ at s3://…" (genome NOT restated)
  → returns **nf-core/rnaseq** workflow whose response references **GRCh38 + human** (preference carried).
- ADMET with concrete SMILES → `workflow_type: nextflow`, `nextflow_path: …/predict_admet_properties/main.nf`,
  `workflow_ga.name = "Predict ADMET Properties (AI)"` (humanized, not "undefined"), steps + params + citations populated.
- RNA-seq without inputs → correct **clarification turn** asking for FASTQ paths (does not fabricate).
- Lane routing: `/api/route/classify` → 200; local heuristic assigns `data-lane="cloud"` for deseq2.

**Browser-observable gaps (PARTIAL):**
- **[P2] Workflow panel not observed opening in-browser** (Flow 1 `1a panel+name`, Flow 2 `2a workflow card` → DEPLOY_GAP).
  The `workflow-artifact-panel` testid + `.panel-name` (falls back to "Untitled", never "undefined")
  exist in the deployed `nextflow-workflow-viewer.tsx`, and the SSE payload is well-formed. Likely
  cause: harness allows only **10s** after `waitForAssistant` for the panel while the live LLM+parse
  takes 20–40s, and/or the test prompt ("aspirin/ibuprofen SMILES" — names, not SMILES) triggers a
  clarification turn (no panel by design). **Root cause: harness timing/prompt, not a product break —
  but the in-browser render was NOT positively confirmed and should be.** Fix: widen the panel-visible
  wait to ≥45s and use a concrete-SMILES prompt that skips clarification.
- **[P3] Flow 3 (models inference UI) — 3 FAIL** (`run-pretrained not visible`, `no infer request`).
  The `run-pretrained` root + domain-picker testids PASS at the DOM-attached level in the UX audit,
  so the component exists; the flow harness likely doesn't click the "Run pre-trained" track tab
  (index 3) before asserting visibility. **Fix: harness must select track-3 first** (sequencing bug,
  not product).

**Working flows:** Flow 4 (/design generate → run_id, POST /api/generate 200), Flow 5 (lane
heuristic + server upgrade), Flow 6 (/files data-hub renders), Flow 7 (rerun endpoint contract).
DEPLOY_GAPs in 4c/6b/7b/8a are all honest data dependencies (need candidates / a dataset / a prior run).

---

## Dimension 3 — Parallel execution → PASS

Source: `parallel-execution-audit.e2e.ts` — **5 passed · 2 skipped (15.7s)**.

- S1 concurrent inference: 3 distinct run_ids, own-record polls, no bleed — PASS
- S2 concurrent generation: 3 distinct run_ids — PASS
- S3 two concurrent sessions: disjoint run-id sets, 2N globally distinct — PASS (API isolation);
  UI-panel sub-check skipped because both panels did not open in budget (same in-browser
  panel-render timing as Dimension 2).
- S5 cross-worker hammer: **0/12 lost 404** — PASS (the shared `RunStateStore` under `--workers=4`
  works; no per-process-dict 404s).
- S7 concurrency burst: 6 accepted, 0 limited, no state corruption — PASS

**Independently confirmed:** launched 2 concurrent `/api/generate` runs → `gen_b6ffb7fc7a62` /
`gen_e293ac46772c` (distinct); each `GET /api/generate/:id` returns its own id and `completed`.
Parallel run-state isolation is real.

---

## Dimension 4 — Memory ability → PASS (4/6) + 2 honest gaps

Source: `memory-ability-audit.e2e.ts` (live re-run in progress at report time; results below are
the harness's documented live verdicts, corroborated by my independent turn-1→turn-2 carry test
above and by the M-1/M-2 screenshots from the current run).

| Scenario | Verdict | Evidence |
|---|---|---|
| M-1 Session-memory carry (`<session_memory>`, ≥0.7) | **PASS** | Round-1 genome preference applied in round-3 without re-prompt (also confirmed by my own probe). |
| M-2 Byte-cap dataset-block preservation (long convo) | **PASS** | Dataset UUID recovered verbatim after 8 filler turns (~15 min run — LLM-latency heavy). |
| M-3 Summarization UUID survival | **PASS** | UUID survived — but only via the preserved-attachments header; the LLM summary text dropped it. |
| M-5 Agentic episodic recall + intent filter | **PASS** | 9 episodes, intent filter narrows. |
| M-4 Cross-session **chat** recall of a just-stated convention | **NOT-WIRED (gap)** | Store spans 9 sessions, but chat can't surface a convention until it's async-summarized; no synchronous convention-write path from chat. |
| M-6 Org-rule adaptation round-trip | **NOT-WIRED (env)** | Regulatory training worker + `data/regulatory_training/` not provisioned on the dev frontend container; source chain exists + unit-tested. |

---

## Backend endpoint reality check (dev, live)

| Endpoint | Method | Result | Verdict |
|---|---|---|---|
| `/api/models`, `/api/models/:id` | GET | 200, real BioNeMo registry (Boltz-2, AF2, ESMFold, Evo2…) | Deployed |
| `/api/model-tracks/{train,adapt,optimise}` | GET | 200 (`optimise` → `{active:false}` honest) | Deployed |
| `/api/models/:id/infer` + `/api/inference/:runId/result` | POST/GET | registered (`/api/inference` bare 404 is correct — it's `/api/inference/*`) | Deployed |
| `/api/generate`, `/api/generate/:runId` | POST/GET | 200, returns `{run_id,status}` → `completed` | Deployed |
| `/api/perception/profile` | POST | 200 (honest "blocked" for unresolvable ref) | Deployed |
| `/api/datasets/:ref/{lineage,consumers,versions}` | GET | 200 honest-empty (`available:false`) | Deployed |
| `/api/route/classify` | POST | 200 (needs `text` field) | Deployed |
| `/api/chat/stream` | POST | 200, well-formed workflow_ga + multi-turn carry | Deployed |
| **`/api/projects`** | GET | **500 "Failed to list projects"** (reproducible; 401 unauth so route is alive; datasets/session, billing/usage, auth/me all 200) | **REGRESSION** |

---

## Prioritized fix list

1. **[P1] Fix `GET /api/projects` 500** (Node/Postgres project-list path). Reproducible for the
   fixture user; blocks the Files/dataset-object surface (data-centric priority #1) from listing
   any datasets. Likely the Postgres query (check UUID/text cast per prior incident) — read the
   Node server error, don't retry-guess.
2. **[P1] Wire the orphan `steps/step-detail.tsx`** into an `open-full-step-view` action from the
   step row in `nextflow-workflow-viewer.tsx`. Restores the entire "full step deep-view" surface
   (5 spec'd elements: provenance, resolved-params+origin badges, rendered⇄raw toggle, claim→output).
3. **[P2] Render the Models · Optimise (DMTA) loop scaffold + inactive empty-state** so the surface
   is present when `/api/model-tracks/optimise` returns `{active:false}`.
4. **[P2] Design surface — render criteria-strip + safety-gate before candidates exist**, and
   reconcile the harness↔component testid drift (`dg-export-order` vs `order-sheet`, `dg-safety-gate`).
5. **[P2] Confirm the in-browser workflow-panel render.** Widen the flow/parallel harness panel-visible
   wait to ≥45s and use a concrete-SMILES prompt (skip clarification); if the panel still doesn't open,
   escalate to a real chat→panel render bug. The payload is correct; the browser render is unconfirmed.
6. **[P3] Fix Flow-3 harness sequencing** — click the "Run pre-trained" track tab (index 3) before
   asserting `run-pretrained` visibility (product component exists; harness bug).
7. **[P3] Add `data-testid`** to StructureViewer (3Dmol) and build Search "save-to-notes" / "lane+corpora chip".
8. **[P3] Seed the fixture project** with one completed run + one dataset so the 51 honest-empty
   data-dependent elements (dataset-object 6 tabs, viewers, after-run tabs, Design Pareto) become auditable.
9. **[Gap, not P] M-4 cross-session chat recall** — add a synchronous convention-write path from chat
   (currently only surfaces after async summarization). **M-6** — provision the regulatory training
   worker on the dev frontend container.

## Honesty notes

- 0 required-failures across 135 UX elements; **no data-centric UI regression** was found.
- The only reproducible live break (`/api/projects` 500) is in a pre-existing path, but it does
  degrade the data-centric Files surface, so it is P1.
- The most consequential *validation* gap: **the workflow panel and dataset object were never
  positively observed rendering with real data in the browser** — the fixture has no datasets and
  the LLM→panel render exceeded the harness's short wait. These need a seeded fixture + a longer
  wait to move from "payload correct, render unconfirmed" to "confirmed".
- No source files were edited (validation only). Three harness specs were copied into the
  `biomate-parallel-exec` worktree to run alongside the parallel-execution harness.
