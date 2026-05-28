# High-Priority Workflow / After-Run Plan (parallelizable)

**Date:** 2026-05-28
**Owner:** yzhang
**Scope:** todo items #23, #24, #26, #27 + v2 7-tab after-run report (= v2-merge Phase 4)
**Branch:** `integration/next-phase`

---

## 1. Goals

| ID | Goal | Why high priority |
|---|---|---|
| **#26** | Assess workflow output visualization gaps across all 29 subworkflow domains | We don't know which workflows render their outputs poorly today — blocks any rollout claim |
| **#27** | Assess after-run panel gaps across all workflows | Same; the v2 redesign should only land if it covers every real workflow output type |
| **#23** | Fix "weird workflow phase index" | Renders `Phase other` when `phase_label` is missing; affects user trust in workflow display |
| **#24** | Add `"BioMate is generating the workflow for you..."` after the AI text response, before the workflow card | Improves perceived latency during the 2-5 s LLM gap |
| **v2 after-run** | 7-tab inline panel (Findings / Outputs / Methods / Parameters / Software / Citations / QC audit) | Replaces the scattered current surface; biggest user-facing win |

---

## 2. Dependency graph

```
    A1 #23 phase index investigation  ─┐
    A2 #26 output viz gap audit       ─┼──►  C v2 7-tab after-run (Phase 4)
    A3 #27 after-run gap audit        ─┘
                                          ▲
    B1 #24 "generating workflow" text ────┘ (informs UI text in v2 too)
```

- **Track A (assessments + #23 fix):** can start immediately, all 3 independent of each other
- **Track B (#24):** independent, can start immediately
- **Track C (v2 7-tab after-run):** waits on Track A completion; needs the gap reports to decide tab-by-tab data sources

---

## 3. Track A — Assessments + phase-index fix (parallel; ~3 dev-days each, can overlap)

### A1 — #23 phase-index investigation + fix

**Symptom (from todo screenshot):** workflow renders phases labeled `Phase other` or with no label at all.

**Where:** `frontend/client/src/components/nextflow-workflow-viewer.tsx:1269`
```ts
const label = (phase.phase_label as string) || `Phase ${key}`;
```
falls back to `Phase ${key}` when `phase_label` is missing; `key = phase.phase_group || 'other'`. So workflows without proper phase annotations show `Phase other`.

**Backend source:** `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py:714-832` parses `// [Phase A] Label …` annotations from the `.nf` source. Workflows without these comments → no labels → frontend fallback fires.

**Deliverables:**
1. Inventory: run a script that scans all 2241 subworkflow `.nf` files for `// [Phase` annotations; produce a CSV: `workflow_path, has_phase_annotations, distinct_groups, distinct_labels`
2. For each annotated workflow, verify the parser extracts groups + labels correctly (no regex bug)
3. For un-annotated workflows: either backfill annotations OR change the frontend fallback to a cleaner `"Step group ${n}"` label
4. Add a defensive lint test: every production workflow under `nextflow_nfcore/subworkflows/` either has `// [Phase X]` comments OR is explicitly in a "single-phase OK" allowlist

**Estimate:** 2 days for one engineer.

**Output:** PR with parser fix (if any bug), backfill commits for top-20 workflows by usage, lint test.

### A2 — #26 Workflow output visualization gap audit

**Question:** for each workflow, are its primary outputs displayed in a useful way (image/table/code/text), or does the user just see a path?

**Scope:** all 29 domains, but practically the **top 20-30 workflows by usage** (DESeq2, sarek, cryosparc_standard_spa, ADMET, PBPK, BOIN, alphafold variants, nf-core/rnaseq, etc.)

**Method:** for each workflow:
1. Run a representative scenario on dev (or use existing E2E artifacts where they exist)
2. Open the run; record what the panel shows: `<img>`, table, code block, raw path, missing
3. Categorize: ✅ first-class viz · ⚠️ shown but ugly · ❌ path only · 🚫 missing entirely

**Deliverables:**
- Audit spreadsheet at `docs/20260528_OUTPUT_VIZ_AUDIT.csv`
- Per-workflow recommendations: which file types need new renderers
- Top-5 priorities for renderer work (e.g. "PNG works, MRC needs cryo-EM viewer; PDB needs molstar")

**Estimate:** 2 days for one engineer with QA help.

### A3 — #27 After-run panel gap audit

**Question:** does each workflow surface enough post-run info for a user to understand "what happened, is it good, can I download it"?

**Areas to audit (using current `nextflow-workflow-viewer.tsx` as baseline):**
- **Findings** card: is anything inline? Or empty for most workflows?
- **Methods report**: does `/api/invocations/:id/methods-report` produce useful prose for this workflow? Or just stub text?
- **Parameters** echo: are submitted params shown back to user?
- **Citations**: which workflows have any?
- **QC audit trail**: does the gate state surface for non-ADMET workflows?

**Deliverables:**
- Audit spreadsheet at `docs/20260528_AFTERRUN_AUDIT.csv` (one row per workflow × tab dimension)
- Per-tab gap list: e.g. "Methods report: only 6 of 30 workflows have a real generator; rest fall back to stub"
- Recommendation: which tabs in the upcoming v2 7-tab panel must be present for v0 launch vs. progressive enhancement

**Estimate:** 2 days for one engineer.

---

## 4. Track B — #24 "Generating workflow" text (parallel; ½ day)

**Where:** `chat-with-artifacts.tsx` — between the AI text-only response chunk completion and the workflow card render (anchor: `onWorkflowGenerated` callback at line 1541).

**Spec:**
- After the AI text response is streamed in full AND the backend has classified the intent as `workflow_generation`, render a small inline status row: `BioMate is generating the workflow for you…` with a subtle spinner
- Show until the workflow card actually appears (i.e. `workflow_ga` is returned)
- Hide instantly when the card mounts

**Deliverables:** one PR, ~30 LOC. Plus a Playwright assertion that the text appears for the LLM gap window.

**Estimate:** ½ day.

---

## 5. Track C — v2 7-tab after-run report (= v2-merge Phase 4)

**Blocked on Track A (A2 + A3) completion.** The audit findings determine:
- Which tabs are needed for v0 (e.g. drop "Citations" if no workflows have any)
- Per-tab data sources (do we need new backend endpoints for Methods/Software?)
- Renderer priorities (which file types must work; which can stay "raw path")

**Once unblocked:**

### C0 — Foundation (½ day, after A complete)
- Same as v2-merge plan Phase 0: copy `frontend/research_agent_v2/src/*` → `frontend/client/src/v2/`
- Namespace CSS tokens
- `useUiFlavor()` hook
- Real-backend wiring via `connectRealBiomateStream`

### C1 — After-run tabs scaffolded (1 day)
- Port `WorkflowPanel.jsx`'s `AfterRunReport` component (7 tabs already wired in v2 mock)
- Connect each tab to a real data adapter; tabs that have no real backend data show "Pending — not yet wired" placeholder rather than fake content

### C2 — Per-tab data wiring (3-4 days, the meat)
- **Outputs tab** — already partly wired (`step-file?download=1`); add image preview where missing
- **Findings tab** — pull from existing `/api/workflows/runs/:id/findings`
- **Methods tab** — pull from `/api/invocations/:id/methods-report` (audit told us which workflows have real generators)
- **Parameters tab** — pull from existing submitted-params state
- **Software tab** — new; needs backend to surface tool versions per run (Phase 4a if not already there)
- **Citations tab** — new; needs cryo-EM-style knowledge enrichment for non-cryo-EM workflows (low-priority v0, ship as "Coming soon")
- **QC audit tab** — pull from existing qc_trace_monitor SSE history

### C3 — Behind `?ui=v2`, validate, flip (1 day)
- Validate against the 6 scenarios from CLAUDE.md UX standard
- Flip default to v2 only after each scenario passes a screenshot + assertion audit
- Keep v1 path live for 1 week as rollback escape

**Estimate:** 5-6 days for one engineer, starting after Track A completes.

---

## 6. Suggested timeline (overlapping)

```
Day 1   ┃ A1 start    A2 start    A3 start    B1 ship
Day 2   ┃ A1, A2, A3 all in flight
Day 3   ┃ A1 PR ready, A2 audit ready, A3 audit ready
        ┃ Track C kickoff (Phase 0 foundation) — C0
Day 4   ┃ C1 after-run tabs scaffolded behind ?ui=v2
Day 5-7 ┃ C2 per-tab wiring
Day 8   ┃ C3 validation + default flip
```

**Total elapsed time:** ~1.5 calendar weeks with two engineers running A and B in parallel, then both joining C.

**Total dev-days:** ~10-11 (A1: 2 + A2: 2 + A3: 2 + B1: 0.5 + C0: 0.5 + C1: 1 + C2: 3.5 + C3: 1).

---

## 7. Coordination notes for parallel work

- **No shared file edits**: Track A1 touches `nextflow-workflow-viewer.tsx:1269` + backend annotation parser. Track B1 touches `chat-with-artifacts.tsx` around line 1541. Track A2/A3 are read-only audits. No PR conflicts.
- **All Track A audit outputs land in `docs/20260528_*_AUDIT.csv`** — Track C reads them as the spec.
- **Daily standup checkpoint**: at end of each day, A leads confirm whether their audit findings change Track C tab scope.
- **Backend changes minimized**: only Software-tab (per-run tool versions) might need new backend; everything else uses existing endpoints. If Software tab is too heavy, ship v0 without it and add later.
- **Feature flag protects v1 path** through Phase 4 + 1 week, per the v2-merge plan rules.

---

## 8. Out of scope (intentionally)

- Other todo items (#9, #12, #14, #15, #18, #20) — separate workstreams, not blockers for v2 after-run
- Auth UI changes — already shipped (BUG-01/04/05/06)
- v2 chat surface + sidebar (Phase 2-3 of merge plan) — can run after Phase 4 ships, or in parallel by a separate engineer once Phase 0 lands
