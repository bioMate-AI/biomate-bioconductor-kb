# Test Plan — Design & Generate / Search & Evidence / Sidebar

**Date:** 2026-09-09
**Branch:** `integration/dev-test`
**Scope:** Three authenticated surfaces, verified against the real source (no invented ids/routes):

| # | Surface | Component (real path) | Route / mount |
|---|---------|-----------------------|---------------|
| A | Design & Generate | `frontend/client/src/components/design-generate/DesignGenerate.tsx` | `/design` (App.tsx:662, wrapped in `AuthenticatedPageLayout`) |
| B | Search & Evidence answer surface | `frontend/client/src/components/citation-panel.tsx` + `frontend/client/src/components/source-reader-pane.tsx` | Rendered inside the chat/answer surface (`CitationPanel` is a child component; no standalone route) |
| C | Sidebar | `frontend/client/src/components/app-sidebar.tsx` | Mounted by `RootRoute` in `App.tsx` (imported line 16; rendered lines 432 & 492 — mobile drawer + desktop rail) |

> **Determinability flags (read before executing):**
> 1. **The deployed authenticated nav IS `app-sidebar.tsx`.** Confirmed: `App.tsx` imports `AppSidebar` from `@/components/app-sidebar` (line 16) and renders it in `RootRoute` (lines 432, 492). There is no `site-header.tsx`. **However, the real sidebar entries DIVERGE from the `CLAUDE.md` "Sidebar" checklist.** The real entries are: New Chat, Workflows, Connectors, IND Report, Data, Models, Design & Generate, Projects (section), chat-history dots, Settings, collapse toggle, logout. **There is NO "Runs → /dashboard" entry** (the `/dashboard` route is commented out in `App.tsx:608`), **NO "CRO Library" entry**, **NO "Billing" sidebar entry** (the `/billing` route exists at `App.tsx:614` but nothing in `app-sidebar.tsx` links to it), **NO "Starred Workflows" or "Recent Tools" entries visibly wired** (a `RecentToolsDialog` is instantiated at line 467 but no button in this file toggles `showRecentToolsDialog`; `WorkflowHistoryDialog` — not a "StarredWorkflowsDialog" — is what the Workflows entry opens). This plan tests the REAL sidebar. Deviations from `CLAUDE.md` are flagged inline as **[SPEC-DRIFT]**.
> 2. **`CitationPanel` renders `null`** when `citations.length === 0 && !methodsSection && !workflow` (line 269). It also has no route — it is a sub-component. Preconditions below assume a parent renders it with a non-empty `citations` prop.
> 3. **`DesignGenerate` uses an injectable `client` prop** (`GenerateClient`) defaulting to real `fetch` against `POST /api/generate` and `GET /api/generate/{id}`. Component/unit tests inject a fake client; E2E hits the real proxy.
> 4. **"Make instruction" button is hard-disabled** (`disabled` attribute, line 344) — no backend endpoint exists. Its test verifies it stays disabled.

---

## Coverage Checklist

| ID | Surface | Element / control | data-testid (real) | Covered by |
|----|---------|-------------------|--------------------|------------|
| A-1 | Design | Entry routes strip | `entry-routes`, `design-entry-dataset`, `design-entry-models`, `design-entry-search` | UC-A01, UC-A02, UC-A03 |
| A-2 | Design | Constraints composer container | `constraints-composer` | UC-A04 |
| A-3 | Design | Seed SMILES input | `dg-seed-smiles` (`#dg-seed`) | UC-A04 |
| A-4 | Design | Scaffold policy toggle (stay/hop/grow) | `dg-scaffold-policy`, `dg-policy-stay`, `dg-policy-hop`, `dg-policy-grow` | UC-A05 |
| A-5 | Design | Property envelope MW/logP/TPSA | `dg-envelope`, `dg-mw`, `dg-logp`, `dg-tpsa` | UC-A06 |
| A-6 | Design | Exclusions SMARTS textarea | `dg-exclusions` | UC-A07 |
| A-7 | Design | Seed series textarea | `dg-seed-series` | UC-A07 |
| A-8 | Design | Count + virtual library size | `dg-count`, `dg-ngenerate` | UC-A08 |
| A-9 | Design | Compute-cost hint | `dg-cost` | UC-A08 |
| A-10 | Design | Run button | `dg-run` | UC-A09, UC-A10 |
| A-11 | Design | Error banner | `dg-error` | UC-A18 |
| A-12 | Design | Run status badge | `dg-status` (`[data-status]`) | UC-A09, UC-A10 |
| A-13 | Design | Notes list | `dg-notes` | UC-A10 |
| A-14 | Design | Empty (no candidates) card | `dg-empty` | UC-A17 |
| A-15 | Design | HitGrid + rows | `hit-grid`, `hit-table`, `hit-row-<id>`, `hit-card-<id>`, `hit-held-note`, `hit-sort-verdict`, `hit-view-<v>`, `hit-model-link` | UC-A11 |
| A-16 | Design | Criteria & weights strip | `criteria-strip`, `criteria-row-<name>`, `criteria-target-<name>`, `criteria-weight-<name>`, `criteria-stated` | UC-A12 |
| A-17 | Design | Order-sheet export | `order-sheet`, `dg-export-order` | UC-A13 |
| A-18 | Design | Multi-objective view | `multi-objective-view`, `mobj-row-<id>`, `obj-<name>` | UC-A11 |
| A-19 | Design | Per-row "why?" | `why-toggle-<id>`, `why-detail-<id>`, `why-version-<id>`, `why-confidence-<id>`, `why-analogue-<id>` | UC-A14 |
| A-20 | Design | Pareto / trade-off view | `pareto-view`, `pareto-svg`, `pareto-point-<id>` (`[data-on-front]`), `pareto-front-path`, `pareto-x-axis`, `pareto-y-axis`, `pareto-empty` | UC-A15 |
| A-21 | Design | Rejection profile | `rejection-profile`, `rejection-cause-<cause>`, `rejection-count-<cause>` | UC-A16 |
| A-22 | Design | Rejected set (safety gate) | `rejected-set`, `rejected-row-<id>`, `rejected-reason-<id>` | UC-A16 |
| A-23 | Design | Predicted-vs-measured | `predicted-vs-measured`, `pvm-empty`, `pvm-row-<id>`, `pvm-cell-<id>-<name>` (`[data-contradiction]`), `pvm-flag-<id>-<name>`, `pvm-contradiction-count` | UC-A17b |
| B-1 | Search | Citation panel container / collapse | (Card; header trigger "Citations") | UC-B01 |
| B-2 | Search | Tool count badge | (`{n}/{total} tools`) | UC-B01 |
| B-3 | Search | Conflict row | `conflict-row` | UC-B02 |
| B-4 | Search | Citation item locus | `citation-locus` | UC-B03 |
| B-5 | Search | Citation recency | `citation-recency` | UC-B03 |
| B-6 | Search | Per-source "open ▸" | `source-open-<index>` | UC-B04 |
| B-7 | Search | "Read" button | `read-<tool_id>` | UC-B04 |
| B-8 | Search | Source reader pane | `source-reader-pane`, `reader-locus`, `reader-open-source`, `reader-prev`, `reader-next` | UC-B04, UC-B05 |
| B-9 | Search | Save to project notes | `answer-save-notes` | UC-B06 (success), UC-B07 (failure), UC-B08 (no-project) |
| B-10 | Search | Make instruction (disabled) | `answer-make-instruction` | UC-B09 |
| B-11 | Search | Export BibTeX | (button "Export BibTeX") | UC-B10 |
| B-12 | Search | Methods tab | (Tab "Methods Section") | UC-B11 |
| C-1 | Sidebar | New Chat | `button-new-chat` | UC-C01 |
| C-2 | Sidebar | Workflows → WorkflowHistoryDialog | `button-workflows-nav`, `workflows-running-badge` | UC-C02 |
| C-3 | Sidebar | Connectors → ConnectorsDialog | `button-connectors-nav` | UC-C03 |
| C-4 | Sidebar | IND Report → `/ind-report` | `button-ind-report` | UC-C04 |
| C-5 | Sidebar | Data → `/files` | `button-data-nav` | UC-C05 |
| C-6 | Sidebar | Models → `/models` | `button-models-nav` | UC-C06 |
| C-7 | Sidebar | Design & Generate → `/design` | `button-design-generate-nav` | UC-C07 |
| C-8 | Sidebar | Projects section toggle | `button-projects-section` | UC-C08 |
| C-9 | Sidebar | Project row + subitems | `button-project-<id>`, `project-link-chats-<id>`, `project-link-files-<id>`, `project-link-workflows-<id>` | UC-C08 |
| C-10 | Sidebar | New project | `button-new-project` | UC-C09 |
| C-11 | Sidebar | Chat history + status dot | `button-chat-<id>`, `history-dot-<id>` | UC-C10 |
| C-12 | Sidebar | Settings (sidebar + footer) | `button-settings-sidebar`, `button-settings` | UC-C11 |
| C-13 | Sidebar | Collapse toggle | `button-sidebar-toggle` | UC-C12 |
| C-14 | Sidebar | Logout | `button-logout` | UC-C13 |
| C-15 | Sidebar | Recent Tools dialog (unwired button) | — (no toggling control in file) | UC-C14 **[SPEC-DRIFT]** |

---

## A. Design & Generate — `components/design-generate/DesignGenerate.tsx`

**Purpose (from the file header):** de-novo molecular design as ONE pipeline (generate → predict activity → optimise properties → rank), holding four commitments: (1) the constraints ARE the interface; (2) NO composite score — each objective in its own units; (3) safety is a GATE (rejected candidates stay visible); (4) honest failure profile (no fabricated shortlist). Data comes from the backend; the component owns only form state, a poll loop, and a pure client-side re-rank.

**Backend contract:** `POST /api/generate` (body = `GenerateRequestBody`) → `{ run_id, status }`; `GET /api/generate/{run_id}` → `GenerationRun`. Polls every 1500 ms while `status === "running"`.

### UC-A01 · Entry route "From a dataset" navigates to the data hub
- **Preconditions/state:** `/design` mounted; no `onStartFromDataset` host override prop passed (App.tsx renders `<DesignGenerate />` with no entry props → default navigation applies).
- **Input:** click "From a dataset".
- **Action flow:** 1. Render `/design`. 2. Locate `entry-routes` strip. 3. Click `design-entry-dataset`.
- **Expected output:** router navigates to `/files?from=design` (exported `ENTRY_ROUTE_TARGETS.dataset`). Button also carries `data-legacy-testid="entry-dataset"` and a title tooltip beginning "An assay table starts a design run directly…".
- **Information flow:** `useLocation()` (wouter) `navigate(ENTRY_ROUTE_TARGETS.dataset)` → URL becomes `/files?from=design` → App.tsx `/files` route renders `DataHubPage`. `?from=design` is a provenance marker only (no hand-off consumer today — navigate-only).
- **Pass criteria:** `window.location.pathname === "/files"` and search contains `from=design`.
- **Edge/error cases:** if a host passes `onStartFromDataset`, the callback fires INSTEAD of navigation (callback precedence). No error state.

### UC-A02 · Entry route "From Models" navigates to the model catalog
- **Preconditions/state:** as UC-A01, no override.
- **Input:** click `design-entry-models`.
- **Action flow:** 1. Click "From Models".
- **Expected output:** navigate to `/models?from=design` (`ENTRY_ROUTE_TARGETS.model`); `/models` renders `ModelsPanel`.
- **Information flow:** `navigate("/models?from=design")` → route match.
- **Pass criteria:** pathname `/models`, search `from=design`.
- **Edge/error cases:** `onStartFromModel` override wins if supplied.

### UC-A03 · Entry route "From Search" navigates to the composer/evidence surface
- **Preconditions/state:** as UC-A01, no override.
- **Input:** click `design-entry-search`.
- **Action flow:** 1. Click "From Search".
- **Expected output:** navigate to `/?from=design` (`ENTRY_ROUTE_TARGETS.search`); root route renders the composer/evidence surface.
- **Information flow:** `navigate("/?from=design")`.
- **Pass criteria:** pathname `/`, search `from=design`.
- **Edge/error cases:** `onPromoteFromSearch` override wins if supplied.

### UC-A04 · Constraints composer renders with defaults; seed SMILES editable
- **Preconditions/state:** fresh `/design`, no run yet.
- **Input:** type `CC(=O)Oc1ccccc1C(=O)O` into the seed field.
- **Action flow:** 1. Assert `constraints-composer` present with heading "Design constraints" and copy "Generation is only useful when constrained…". 2. Type SMILES into `dg-seed-smiles`.
- **Expected output:** input reflects typed value; placeholder before typing is `e.g. CC(=O)Oc1ccccc1C(=O)O`.
- **Information flow:** local `seedSmiles` state → folded into `buildBody().constraints.seed_smiles` (trimmed; `undefined` if empty).
- **Pass criteria:** `dg-seed-smiles` value equals typed string.
- **Edge/error cases:** empty seed → `seed_smiles: undefined` in the request body (allowed).

### UC-A05 · Scaffold policy toggle (Stay / Hop / Grow)
- **Preconditions/state:** default policy is `stay` (button variant `default`, others `outline`).
- **Input:** click `dg-policy-hop`, then `dg-policy-grow`.
- **Action flow:** 1. Assert `dg-policy-stay` is the active (default variant) button initially. 2. Click `dg-policy-hop` → it becomes active. 3. Click `dg-policy-grow` → it becomes active.
- **Expected output:** exactly one of the three buttons is `variant="default"` at a time (the selected one); labels are capitalized (stay/hop/grow).
- **Information flow:** `setScaffoldPolicy(p)` → `buildBody().constraints.scaffold_policy`.
- **Pass criteria:** clicked policy carries the active styling; `scaffold_policy` in the next request equals the selection.
- **Edge/error cases:** only three canonical values (`SCAFFOLD_POLICIES`); no free entry.

### UC-A06 · Property envelope MW / logP / TPSA edit
- **Preconditions/state:** defaults `MW=500`, `logP=5`, `TPSA=140`.
- **Input:** set MW=450, logP=4, TPSA=120.
- **Action flow:** 1. Assert `dg-envelope` grid shows three labelled inputs (`MW ≤`, `logP ≤`, `TPSA ≤`). 2. Edit `dg-mw`, `dg-logp`, `dg-tpsa`.
- **Expected output:** inputs reflect new values; label copy states "a window, not a cut-off".
- **Information flow:** each string state → `num(...)` (finite-guarded `parseFloat`) → `property_envelope.{mw_max,logp_max,tpsa_max}`. Non-numeric → `undefined`.
- **Pass criteria:** request body carries the three numeric maxima.
- **Edge/error cases:** blank/`abc` → that field omitted (undefined), no crash.

### UC-A07 · Exclusions SMARTS + seed series parsed as lists
- **Preconditions/state:** both textareas empty by default.
- **Input:** `dg-exclusions` = `[N+](=O)[O-]` (one per line); `dg-seed-series` = two SMILES on separate lines.
- **Action flow:** 1. Fill `dg-exclusions`. 2. Fill `dg-seed-series`.
- **Expected output:** values reflected; exclusions placeholder `[N+](=O)[O-]`, seed-series placeholder "One SMILES per line".
- **Information flow:** `parseList(t)` splits on `[\n,]`, trims, drops empties → `constraints.exclusions[]` and `seed_series[]`.
- **Pass criteria:** request body `exclusions` and `seed_series` are the parsed arrays.
- **Edge/error cases:** empty → `[]`; comma-and-newline mixed input still parses to a clean array.

### UC-A08 · Count + virtual library size + compute cost hint
- **Preconditions/state:** defaults `count=20`, `nGenerate=200`.
- **Input:** set count=40, virtual library size=400.
- **Action flow:** 1. Read `dg-cost` initial text. 2. Edit `dg-count` and `dg-ngenerate`. 3. Re-read `dg-cost`.
- **Expected output:** `dg-cost` reads `Compute cost before run: ~N compute unit(s)` where `N = max(1, round((nGenerate+count)/50))` (e.g. defaults → `~4 compute units`; 40+400 → `~9 compute units`). Singular "unit" when N=1.
- **Information flow:** `estimateCost(count, nGenerate)` recomputed on every render from the two parsed ints. This is a UI heuristic, explicitly "not a billing figure".
- **Pass criteria:** displayed unit count matches the formula for the entered numbers.
- **Edge/error cases:** non-numeric count/nGenerate → parsed as 0 in the cost hint; `buildBody` floors count/n_generate to ≥1 (`|| 20` / `|| 200` defaults).

### UC-A09 · Run start → running state (badge + disabled button)
- **Preconditions/state:** inject a `client` whose `start` resolves `{ run_id: "r1", status: "running" }` and whose `poll` (first call) returns `{ run_id:"r1", status:"running" }`.
- **Input:** click `dg-run`.
- **Action flow:** 1. Click `dg-run`. 2. Observe immediate state.
- **Expected output:** `dg-status` badge shows `running` with `data-status="running"`; the run button label changes to "Running…" and is `disabled` (`running === true`). Poll loop schedules a 1500 ms retry.
- **Information flow:** `onRun()` → `client.start(buildBody())` → `setRun({run_id,status:"running"})` → `pollLoop(run_id)` (setTimeout 1500). `running = run?.status === "running"` disables `dg-run`.
- **Pass criteria:** button disabled + "Running…" label; badge `data-status="running"`.
- **Edge/error cases:** a second click while running is blocked by `disabled`.

### UC-A10 · Poll resolves to completed → status/notes/generator line
- **Preconditions/state:** injected `client.poll` returns a completed `GenerationRun` with `generator:"brics"`, `generator_is_learned:false`, `n_generated:200`, `n_scored:180`, `notes:["…"]`, plus candidates/objectives.
- **Input:** none beyond UC-A09 run.
- **Action flow:** 1. Run. 2. Let poll resolve to `completed`.
- **Expected output:** `dg-status` badge `data-status="completed"` reading `completed`; the status line shows `generator: brics (deterministic enumeration, not learned)`, `generated: 200`, `scored: 180`. `dg-notes` renders each note as a `<li>`.
- **Information flow:** `poll` result → `setRun(r)`; because `status !== "running"` the poll loop stops. `useEffect` reseeds `criteria` from `seedCriteria(objectives, candidates)` on the completed run.
- **Pass criteria:** badge completed; generator/generated/scored line present; notes list matches `run.notes`.
- **Edge/error cases:** if `generator_is_learned !== false`, the "(deterministic enumeration…)" suffix is omitted.

### UC-A11 · Completed results render HitGrid + Multi-objective view (no composite)
- **Preconditions/state:** completed run with ≥2 candidates carrying `objectives[]` and ≥1 with `verdict:"held"`.
- **Input:** none.
- **Action flow:** 1. Complete a run. 2. Inspect `hit-grid`, `multi-objective-view`.
- **Expected output:**
  - `hit-grid` present with `hit-table`; each candidate a `hit-row-<id>`; a `held` candidate shows the `hit-held-note`.
  - `multi-objective-view` present; header copy "Each objective keeps its own units and its own target — no single blended number." Each objective column header shows `name /unit`; the `score*` column header carries `title="Ranking key only"`; footer note states score "is a ranking key… not a composite the pipeline optimises."
  - Each `mobj-row-<id>` renders one `obj-<name>` cell per objective, colored green when the target is met (per direction), amber when not, slate when no target.
- **Information flow:** `candidates` (backend order, or re-ranked — see UC-A12) → `toHit()` → HitGrid; and → `MultiObjectiveView`. `ObjectiveCell` computes `meetsTarget` from `direction` + `target`.
- **Pass criteria:** both views render; no single "composite score" is presented as the headline; held candidate visible (not filtered).
- **Edge/error cases:** objective missing on a candidate → cell shows `n/a` (italic).

### UC-A12 · Editable criteria/weights re-rank WITHOUT a re-run
- **Preconditions/state:** completed run; `criteria-strip` visible; `criteria` seeded from run.
- **Input:** change a weight in `criteria-weight-<name>` (e.g. bump one objective's weight to 5) and/or set a `criteria-target-<name>`.
- **Action flow:** 1. Note current HitGrid/`mobj` row order. 2. Edit a weight. 3. Observe reorder. 4. Assert NO new `client.start`/`client.poll` call fires.
- **Expected output:** `criteria-stated` line updates (`Ranking criteria: <name> (↑ ≥ t, w=5) · …`); HitGrid + `multi-objective-view` rows reorder; held candidates sort to the end and keep place-nowhere status.
- **Information flow:** `updateCriterion(name, patch)` → `criteria` state → `useMemo` `reRank(rawCandidates, criteria)` (pure client-side re-sort via `rankKey`/`desirability`) → `candidates` → HitGrid + views. **NO backend call.** This is the §5.4 rule: "changing them re-ranks WITHOUT re-running the predictions."
- **Pass criteria:** order changes AND the injected client's `start`/`poll` call counts are unchanged after the edit.
- **Edge/error cases:** weight `0` on an objective → that objective excluded from `rankKey` (num/den skip); all-zero weights → `rankKey` falls back to `c.score`. Empty target string → `target:null` (direction still orders).

### UC-A13 · Export order sheet (candidate + registry id CSV)
- **Preconditions/state:** completed run with ≥1 candidate + `objectives[]`.
- **Input:** click `dg-export-order`.
- **Action flow:** 1. Assert `order-sheet` strip present with copy "Leave the platform as an order…". 2. Click `dg-export-order`.
- **Expected output:** a client-side CSV blob download named `order-sheet-<run_id>.csv` (or `order-sheet-design.csv` if no run id). Header: `rank,candidate_id,registry_id,smiles,verdict,score,<obj (unit)>…`; each row's `registry_id` is `REG-<candidate_id>`; objective values in their own units; rows in the CURRENT (re-ranked) order.
- **Information flow:** `buildOrderSheetCsv(candidates, objectiveMeta)` (RFC-4180-ish `csvField` quoting) → `Blob` → `URL.createObjectURL` → anchor click → `revokeObjectURL`.
- **Pass criteria:** downloaded content parses to the expected header + rows; `registry_id` prefix present.
- **Edge/error cases:** `candidates.length === 0` → button `disabled` (no export). SMILES containing commas/quotes → quoted per RFC-4180.

### UC-A14 · Per-row "why?" drill-in (model / version / confidence / analogue)
- **Preconditions/state:** completed run.
- **Input:** click `why-toggle-<id>` on a `mobj-row`.
- **Action flow:** 1. Click `why-toggle-<id>` (`aria-expanded` flips to true). 2. Inspect `why-detail-<id>`.
- **Expected output:** `why-detail-<id>` row shows: **Model** = `<generator> + objective predictors (<name>/<unit>, …)`; **Version** (`why-version-<id>`) = `deterministic enumeration (unversioned)` when `generator_is_learned === false`, else the generator name; **Confidence** (`why-confidence-<id>`) = the candidate's `confidence` (capitalized); a "What drove it" line listing per-objective values; **Nearest measured analogue** (`why-analogue-<id>`) = "not available — no measured assay series was returned with this run". If verdict is `held`, an amber "Held — outside the model's applicability region…" note appears.
- **Information flow:** `whyProvenance` derived from `run.generator`/`generator_is_learned`/objectives; `WhyRow` renders it + the candidate's own objectives — no fabricated analogue.
- **Pass criteria:** all four labelled fields populated from real run data; analogue honestly states unavailability.
- **Edge/error cases:** candidate with empty `objectives` → "no per-objective values available".

### UC-A15 · Pareto / trade-off view (front highlighted, axis re-pick)
- **Preconditions/state:** completed run with ≥2 objectives and a non-empty `pareto[]` (SMILES on the front).
- **Input:** view render; then change `pareto-x-axis` / `pareto-y-axis`.
- **Action flow:** 1. Assert `pareto-view` + `pareto-svg`. 2. Confirm each candidate = `pareto-point-<id>`; front members carry `data-on-front="true"` and larger radius / indigo fill; `pareto-front-path` drawn when ≥2 front points. 3. Re-pick an axis via the selects.
- **Expected output:** front dots highlighted; gate-rejected dots red; held dots slate; legend shows on-front count. Header copy "The trade-off is shown, not collapsed."
- **Information flow:** `paretoSmiles` (`run.pareto`) → `Set`; each candidate matched by SMILES → `onFront`. Axis selects drive `xName`/`yName` local state → point coordinates recomputed (pure, no backend).
- **Pass criteria:** front points flagged `data-on-front="true"`; axis change re-plots without a network call.
- **Edge/error cases:** `< 2` objectives → `pareto-empty` ("A trade-off needs two objectives…"). No candidate carries both selected objectives → `pareto-empty` ("No candidate carries both selected objectives…"). Empty `pareto[]` → note "No front members were returned for this run."

### UC-A16 · Rejection profile by cause + rejected set stays visible with reason
- **Preconditions/state:** completed run with `rejected[]` carrying mixed reasons (e.g. "structural alert: nitro_group", "banned moiety: …", "invalid structure (unparseable)").
- **Input:** none; then expand `rejected-set`.
- **Action flow:** 1. Assert `rejection-profile` present with total badge. 2. Confirm one `rejection-cause-<cause>` row per bucket with `rejection-count-<cause>`. 3. Click `rejected-set` header to expand. 4. Confirm each `rejected-row-<id>` shows id + `rejected-reason-<id>` + SMILES.
- **Expected output:** reasons bucketed by `classifyRejection` into `structural_alert / banned_moiety / sa_floor / valence / other`, rendered in that fixed order with human labels; `passedNote` "`<n_scored>` scored of `<n_generated>` generated" when both counts present. Rejected candidates are NEVER filtered — they remain visible with the gate reason (red left-border rows).
- **Information flow:** `run.rejected` → `RejectionProfile` (bucket + count) AND `RejectedSet` (collapsible list). Both render from the same array.
- **Pass criteria:** each distinct cause bucketed correctly; rejected rows visible with reason text.
- **Edge/error cases:** `rejected.length === 0` → both `rejection-profile` and `rejected-set` render `null` (nothing). Unrecognized reason → `other` bucket.

### UC-A17 · Honest empty state (no candidates cleared)
- **Preconditions/state:** completed run with `candidates: []` (and typically a populated `rejected[]`).
- **Input:** none.
- **Action flow:** 1. Complete a run that yields zero kept candidates.
- **Expected output:** `dg-empty` card: "No candidates cleared the pipeline. The failure profile is above… Nothing was fabricated to fill a shortlist." Followed by `rejection-profile`. No HitGrid, no criteria strip, no order sheet (those are gated on `candidates.length > 0`).
- **Information flow:** `run.status === "completed" && candidates.length === 0` branch → empty card + `RejectionProfile`.
- **Pass criteria:** `dg-empty` shown; no fabricated candidates; rejection profile explains why.
- **Edge/error cases:** completed with zero candidates AND zero rejected → `dg-empty` only (profile renders null).

### UC-A17b · Predicted-vs-measured (contradiction flag)
- **Preconditions/state:** completed run with candidates; supply `measuredResults` prop with at least one measured objective whose value diverges >50% from the prediction.
- **Input:** none (prop-driven).
- **Action flow:** 1. Complete a run. 2. Pass `measuredResults=[{id, registryId?, measured:[{name,value,unit}]}]`. 3. Inspect `predicted-vs-measured`.
- **Expected output:** `predicted-vs-measured` shows `pvm-row-<id>` per measured candidate; each `pvm-cell-<id>-<name>` renders `pred → meas`; a divergence >tol sets `data-contradiction="true"`, colors the measured value red, and appends `pvm-flag-<id>-<name>` ("contradiction"). Header badge `pvm-contradiction-count` = "N flagged".
- **Information flow:** `isContradiction(pred, meas, 0.5)` (relative diff with 1e-6 floor) per cell → contradiction flags aggregated into the badge. No refit is run here (design-side record only).
- **Pass criteria:** contradiction cell flagged; count badge correct.
- **Edge/error cases:** no `measuredResults` → `pvm-empty` ("No measured results yet…"). A measured id not matching any candidate → row dropped. Missing prediction/measure → cell shows `n/a`/`—`.

### UC-A18 · Backend failure surfaces honestly (error banner)
- **Preconditions/state:** inject a `client.start` that rejects (e.g. throws `start failed: 500`).
- **Input:** click `dg-run`.
- **Action flow:** 1. Click run. 2. `start` rejects.
- **Expected output:** `dg-error` banner shows the stringified error; no fake results render; run button not stuck in "Running…" (run state never set to running because `start` threw before `setRun`).
- **Information flow:** `onRun` try/catch → `setError(String(e))` → `dg-error`. A `poll` rejection mid-run also routes to `setError`.
- **Pass criteria:** `dg-error` visible with the real error string; no fabricated candidate view.
- **Edge/error cases:** poll rejects after start succeeded → error banner shown but the last known `run` (running badge) may persist until re-run.

---

## B. Search & Evidence — `citation-panel.tsx` + `source-reader-pane.tsx`

**Purpose:** the answer's evidence surface (Spec 01). Lists cited sources with locus + recency, surfaces source-vs-source conflicts honestly, opens a right-hand reader per source with prev/next, and provides the two sanctioned answer→project exits ("Save to notes", "Make instruction") plus BibTeX export and a Methods-section tab. Nothing is fabricated: conflict rows and loci only render when the retrieval path supplies them.

**Render guard:** returns `null` if `citations.length === 0 && !displayMethodsSection && !workflow` (line 269). Preconditions below assume a non-empty `citations` prop with items carrying `doi || pmid || title` (only those become `toolsWithCitations`).

### UC-B01 · Panel collapse/expand + tool count badge
- **Preconditions/state:** `CitationPanel` rendered with `isCollapsed` default true → starts collapsed; 3 of 4 citations have DOI/PMID/title.
- **Input:** click the "Citations" header trigger.
- **Action flow:** 1. Assert header shows book icon + "Citations" + badge `3/4 tools`. 2. Click trigger to expand. 3. Confirm the tabs ("Tool Citations", "Methods Section") appear.
- **Expected output:** collapsed→expanded toggles the `CollapsibleContent`; badge text = `{toolsWithCitations.length}/{totalTools} tools`.
- **Information flow:** `citations` prop → `toolsWithCitations = citations.filter(c => c.doi||c.pmid||c.title)`; `isExpanded` local state drives the Collapsible.
- **Pass criteria:** badge count correct; content shows/hides on toggle.
- **Edge/error cases:** all citations lack doi/pmid/title → tab body shows "No citations available for tools in this workflow".

### UC-B02 · Conflict row ("sources disagree", both positions)
- **Preconditions/state:** `conflicts` prop supplied with ≥1 entry whose `positions.length > 0` (e.g. `{topic:"Effect at physiological dose", positions:[{claim, source}, {claim, source}]}`).
- **Input:** click the conflict row to expand.
- **Action flow:** 1. Expand the panel. 2. Assert `conflict-row` present in the Citations tab, above the source list. 3. Click it. 4. Confirm both positions render side by side with their sources.
- **Expected output:** collapsed label "Sources disagree — N conflicting finding(s)" (amber flag icon); expanded shows each conflict's `topic` and every position's `claim` with `— <source>`. Disagreement is NOT resolved by preferring newer/more-cited.
- **Information flow:** `activeConflicts = (conflicts||[]).filter(c => c.positions?.length>0)` → `ConflictRow`; `conflictsExpanded` local state toggles the body.
- **Pass criteria:** row renders only when a real conflict is passed; both positions + sources visible on expand.
- **Edge/error cases:** `conflicts` undefined/empty, or all positions empty → `conflict-row` never renders.

### UC-B03 · Citation item shows locus ("cited for") + recency
- **Preconditions/state:** a citation carrying `locus:"Fig 3B"`, `retrieval_date:"2026-08-01"`, `corpus_version:"pubmed-2026-07"`.
- **Input:** expand that citation item.
- **Action flow:** 1. Expand the panel. 2. Click the citation item's chevron to expand it. 3. Inspect the body.
- **Expected output:** `citation-locus` line: map-pin + "cited for: Fig 3B" (a compact locus badge also shows in the collapsed row header when present). `citation-recency` line: "Retrieved 2026-08-01 · pubmed-2026-07". DOI/PMID links render as external anchors.
- **Information flow:** `EvidenceCitation` widened fields (`locus`, `retrieval_date`, `corpus_version`) → rendered only when present (`hasRecency` guard). No fabrication.
- **Pass criteria:** locus + recency lines present and correct.
- **Edge/error cases:** citation without locus → no `citation-locus`; without recency fields → no `citation-recency`.

### UC-B04 · Per-source "open ▸" and "Read" open the SourceReaderPane
- **Preconditions/state:** ≥2 `toolsWithCitations`.
- **Input:** click `source-open-0` (inline "open ▸" on the first source).
- **Action flow:** 1. Expand panel. 2. Click `source-open-0`. 3. Confirm `source-reader-pane` opens on the right at that source. 4. (Alt) expand a citation and click `read-<tool_id>` — same effect at that index.
- **Expected output:** `source-reader-pane` (a right-side Sheet) opens showing "Source 1 of N", title/venue/year, `reader-locus` ("cited for:" badge) when present, recency line when present, and either `reader-open-source` (external link to DOI/PubMed) or "No DOI or PubMed link available for this source."
- **Information flow:** `setReaderIndex(idx)` → `SourceReaderPane` `index` prop → `open = index!==null && in range`; `sourceUrl(c)` resolves DOI→PubMed→null. Full text is intentionally NOT shown (honest "open at source" fallback).
- **Pass criteria:** reader opens at the clicked source; "Source X of N" correct.
- **Edge/error cases:** source with no DOI/PMID → italic "No DOI or PubMed link available"; closing the Sheet sets index back to null.

### UC-B05 · Source reader prev/next navigation
- **Preconditions/state:** reader open at index 0 of N≥3 sources.
- **Input:** click `reader-next`, then `reader-prev`.
- **Action flow:** 1. Open reader at index 0. 2. Assert `reader-prev` disabled at index 0. 3. Click `reader-next` → index 1 (header "Source 2 of N"). 4. Click `reader-prev` → back to 0. 5. Navigate to last index; assert `reader-next` disabled.
- **Expected output:** header count and body update per index; boundary buttons disabled at ends (`reader-prev` disabled at 0, `reader-next` disabled at N-1).
- **Information flow:** `goPrev`/`goNext` call `onIndexChange(index±1)` guarded by bounds.
- **Pass criteria:** navigation walks the ordered source list; boundaries disabled.
- **Edge/error cases:** single source → both prev and next disabled.

### UC-B06 · Save to project notes — SUCCESS
- **Preconditions/state:** an active project is selected (`useActiveProjectIdSafe()` returns an id); ≥1 cited source; optionally `answerText` supplied.
- **Input:** click `answer-save-notes`.
- **Action flow:** 1. Expand panel. 2. Assert `answer-save-notes` is ENABLED (tooltip "Save this answer and its sources to the project's notes"). 3. Click it. 4. Confirm spinner then success toast.
- **Expected output:** a toast "Saved to project notes" / "The answer and its sources were added to this project." The saved markdown includes `answerText` (if present) + a "## Sources" list, each entry with label, venue·year, `cited for: <locus>` (when present), and the resolved URL.
- **Information flow:** `handleSaveToNotes` → `buildNoteMarkdown()` → `api.request('/memory/projects/<activeProjectId>/knowledge', POST, { knowledgeType:'notes_synthesis', title:'Saved answer — <YYYY-MM-DD>', content, source:'user_saved' })`. Real endpoint: `POST /api/memory/projects/:id/knowledge`. **[E2E note: NEVER mock this — hit the real endpoint with the fixture account + an active project.]**
- **Pass criteria:** POST returns 2xx; success toast shown; button spinner clears (`isSavingNote` false).
- **Edge/error cases:** content empty (no answer text AND no cited sources) → destructive toast "Nothing to save" and NO POST.

### UC-B07 · Save to project notes — FAILURE
- **Preconditions/state:** active project selected; force the endpoint to fail (E2E: use a project id the user does not own → 403/404; or a network fault).
- **Input:** click `answer-save-notes`.
- **Action flow:** 1. Click save. 2. `api.request` rejects.
- **Expected output:** destructive toast "Could not save" / "<error message or 'Saving to project notes failed.'>". Console logs `[citations] save to notes failed:`. `isSavingNote` resets (button re-enabled).
- **Information flow:** `handleSaveToNotes` catch → `toast({variant:'destructive'})`; finally → `setIsSavingNote(false)`.
- **Pass criteria:** failure toast shown; button not stuck spinning; no fake success.
- **Edge/error cases:** double-click while saving → guarded by `isSavingNote` early-return.

### UC-B08 · Save to project notes — NO active project (disabled)
- **Preconditions/state:** no active project (`useActiveProjectIdSafe()` returns null/undefined).
- **Input:** hover `answer-save-notes`.
- **Action flow:** 1. Assert `answer-save-notes` is `disabled`. 2. Hover the wrapping span. 3. Read tooltip.
- **Expected output:** button disabled; tooltip "Select a project to save this answer to its notes". A `<span>` wraps the disabled button so the tooltip still fires on hover.
- **Information flow:** `disabled={!activeProjectId || isSavingNote}`; tooltip text branches on `activeProjectId`.
- **Pass criteria:** disabled state + correct tooltip; clicking does nothing (early return).
- **Edge/error cases:** none beyond the disabled guard.

### UC-B09 · "Make a project instruction" — honestly disabled
- **Preconditions/state:** any (button hard-disabled regardless of project).
- **Input:** hover `answer-make-instruction`.
- **Action flow:** 1. Assert `answer-make-instruction` is `disabled` unconditionally (no backend endpoint). 2. Hover. 3. Read tooltip.
- **Expected output:** button disabled; tooltip "Promote to a standing project instruction — coming soon". No POST fires on click.
- **Information flow:** static `disabled` attribute (line 344) — the project-instructions store has no write endpoint yet.
- **Pass criteria:** always disabled; tooltip "coming soon"; no network call.
- **Edge/error cases:** **[SPEC-DRIFT vs task brief]** — the brief lists "Make a project instruction" as a working exit; the real component intentionally ships it disabled to avoid fabricating a success.

### UC-B10 · Export BibTeX
- **Preconditions/state:** ≥1 `toolsWithCitations`; a `workflow` prop present (API export) OR citations carrying `formatted_bibtex` (fallback).
- **Input:** click "Export BibTeX".
- **Action flow:** 1. Click the button. 2. Observe spinner then download.
- **Expected output:** with `workflow`: calls `exportCitationsBibTeX(workflow, true)` and downloads `workflow_citations.bib`. Without `workflow` (or on API failure): falls back to concatenating `formatted_bibtex` and downloads the same filename.
- **Information flow:** `handleExportAll` → API or `fallbackExport()` → `downloadAsFile(..., 'workflow_citations.bib', 'application/x-bibtex')`.
- **Pass criteria:** a `.bib` file downloads; button spinner clears (`isExporting` false).
- **Edge/error cases:** no `formatted_bibtex` and no workflow → nothing downloads (fallback produces empty content, no file). Button only rendered when `toolsWithCitations.length > 0`.

### UC-B11 · Methods Section tab (regenerate + copy)
- **Preconditions/state:** a `workflow` prop present (enables generation); tab enabled.
- **Input:** open "Methods Section" tab; change Style select; click Regenerate; click Copy.
- **Action flow:** 1. Click the "Methods Section" tab. 2. If no section yet, click "Generate Methods Section". 3. Change Style (short/apa/numbered) → regenerates. 4. Click "Regenerate". 5. Click "Copy".
- **Expected output:** methods text renders in a read-only textarea; "N tool(s) cited" and any "N tool(s) missing citations" shown; Copy shows a green check for 2s.
- **Information flow:** `handleRegenerateMethodsSection(style)` → `generateMethodsSection(workflow, style)` → `localMethodsSection` + `onMethodsSectionUpdated?`. Copy → clipboard.
- **Pass criteria:** methods text populated; style change triggers a regenerate call; copy feedback shown.
- **Edge/error cases:** tab `disabled` when `!displayMethodsSection && !workflow`; without workflow → "Methods section not available".

---

## C. Sidebar — `app-sidebar.tsx`

**Purpose:** the primary authenticated workspace nav. Mounted by `RootRoute` in `App.tsx` (desktop rail + mobile drawer). Provides workspace entries, a Projects tree, chat history with live status dots, settings, collapse, and logout.

> **[SPEC-DRIFT]** This real sidebar does not match the `CLAUDE.md` "Sidebar" checklist. Missing entirely: "Runs → /dashboard" (route commented out), "CRO Library", a "Billing" link, "Starred Workflows" and "Recent Tools" as visible entries. Present instead: Connectors, IND Report, Data, Models, Design & Generate. Each UC below tests the REAL element.

### UC-C01 · New Chat
- **Preconditions/state:** authenticated; sidebar rendered.
- **Input:** click `button-new-chat`.
- **Action flow:** 1. Click "New Chat".
- **Expected output:** the `onNewChat` prop fires (App.tsx starts a fresh chat session; mobile also closes the drawer). Subtext "Start a fresh AI conversation".
- **Information flow:** `onClick={onNewChat}` → parent handler in `RootRoute`.
- **Pass criteria:** new-chat handler invoked (new session created / composer cleared).
- **Edge/error cases:** default prop logs to console if unwired (component-test context only).

### UC-C02 · Workflows → WorkflowHistoryDialog (+ running badge)
- **Preconditions/state:** authenticated; the runs-overview poll may set `runningCount`.
- **Input:** click `button-workflows-nav`.
- **Action flow:** 1. Assert subtext "Run history, browse & import pipelines". 2. If runs are in flight, assert `workflows-running-badge` shows the count. 3. Click. 4. Confirm `WorkflowHistoryDialog` opens (initial tab "runs").
- **Expected output:** dialog opens; analytics `workflows_sidebar_opened` tracked. **[SPEC-DRIFT]** this is `WorkflowHistoryDialog`, NOT a "StarredWorkflowsDialog".
- **Information flow:** `onClick` → `analytics.track` + `setHistoryInitialTab('runs')` + `setShowHistoryDialog(true)`. Badge from `GET /api/workflows/runs/overview?scope=all_chats&status=running&limit=1` (polled every 30s) → `runningCount`.
- **Pass criteria:** dialog opens on "runs" tab; badge count matches the overview total when >0.
- **Edge/error cases:** overview fetch fails → `runningCount` stays 0, no badge (silent catch).

### UC-C03 · Connectors → ConnectorsDialog
- **Preconditions/state:** authenticated.
- **Input:** click `button-connectors-nav`.
- **Action flow:** 1. Assert subtext "Databases, LLMs & platform integrations". 2. Click.
- **Expected output:** `ConnectorsDialog` opens (`showConnectorsDialog` true).
- **Information flow:** `onClick` → `setShowConnectorsDialog(true)`.
- **Pass criteria:** connectors dialog visible.
- **Edge/error cases:** none.

### UC-C04 · IND Report → `/ind-report`
- **Preconditions/state:** authenticated.
- **Input:** click `button-ind-report`.
- **Action flow:** 1. Click "IND Report".
- **Expected output:** `setLocation('/ind-report')` → App.tsx renders `IndReportPage` (route line 638).
- **Information flow:** wouter `setLocation`.
- **Pass criteria:** pathname `/ind-report`; IND report page mounts.
- **Edge/error cases:** none.

### UC-C05 · Data → `/files`
- **Preconditions/state:** authenticated.
- **Input:** click `button-data-nav`.
- **Action flow:** 1. Click "Data".
- **Expected output:** `setLocation('/files')` → `DataHubPage` (route line 673). Subtext "Datasets, quality & lineage".
- **Information flow:** wouter `setLocation`.
- **Pass criteria:** pathname `/files`; data hub mounts.
- **Edge/error cases:** none.

### UC-C06 · Models → `/models`
- **Preconditions/state:** authenticated.
- **Input:** click `button-models-nav`.
- **Action flow:** 1. Click "Models".
- **Expected output:** `setLocation('/models')` → `ModelsPanel` (route line 654). Subtext "Train, adapt & run models · registry".
- **Information flow:** wouter `setLocation`.
- **Pass criteria:** pathname `/models`.
- **Edge/error cases:** none.

### UC-C07 · Design & Generate → `/design`
- **Preconditions/state:** authenticated.
- **Input:** click `button-design-generate-nav`.
- **Action flow:** 1. Click "Design & Generate".
- **Expected output:** `setLocation('/design')` → `DesignGenerate` (route line 662). Subtext "Generate candidates against property objectives".
- **Information flow:** wouter `setLocation`.
- **Pass criteria:** pathname `/design`; the Design surface (`design-generate` container) mounts — chains into Surface A UCs.
- **Edge/error cases:** none.

### UC-C08 · Projects section — toggle, expand a project, subitems navigate
- **Preconditions/state:** authenticated with ≥1 project returned by `GET /api/projects`.
- **Input:** toggle `button-projects-section`; click `button-project-<id>`; click a subitem.
- **Action flow:** 1. Assert `button-projects-section` (label "Projects") expands/collapses the list. 2. Click `button-project-<id>` → `onProjectSelect(id)` fires and the row expands to reveal Chats/Files/Workflows. 3. Click `project-link-chats-<id>` / `project-link-files-<id>` / `project-link-workflows-<id>`.
- **Expected output:** subitems navigate to `/projects?project=<id>&tab=chat` / `&tab=files` / `&tab=workflows`. A "shared" tag shows when `proj.userId !== user.id`.
- **Information flow:** projects from `GET /api/projects` (`.slice(0,12)`), refreshed on the `biomate:projects-updated` window event. Subitem clicks → `setLocation('/projects?project=<id>&tab=<t>')`.
- **Pass criteria:** section toggles; project row selects + expands; each subitem routes to the correct tab.
- **Edge/error cases:** projects fetch fails → empty list (silent catch). No projects → only the "New project" row shows.

### UC-C09 · New project
- **Preconditions/state:** authenticated.
- **Input:** click `button-new-project`.
- **Action flow:** 1. Click "New project".
- **Expected output:** `onNewProject` prop fires (parent opens the new-project flow).
- **Information flow:** `onClick={onNewProject}`.
- **Pass criteria:** new-project handler invoked.
- **Edge/error cases:** default prop logs if unwired (component-test only).

### UC-C10 · Chat history + live status dot
- **Preconditions/state:** `chatSessions` prop non-empty; `GET /api/workflows/runs?limit=50` returns runs mapping to sessions.
- **Input:** click `button-chat-<id>`; observe `history-dot-<id>`.
- **Action flow:** 1. Assert up to 6 chats under "Current" and up to 6 more under "Recent" (when >6). 2. Read `history-dot-<id>` color/title. 3. Click a chat row.
- **Expected output:** dot color = blue (running) / red (failed) / green (completed) / grey (idle/none); running dots pulse. Clicking fires `onChatSelect(id)`; the active row is highlighted. Empty → "No chats yet".
- **Information flow:** `fetchSessionStatuses` (polled every 15s) buckets each run's `execution.status` into running/failed/completed (running > failed > completed precedence) → `sessionStatusMap` → dot color per session. **[Note]** the Recent group (rows 6–12) renders a spacer, NOT a status dot.
- **Pass criteria:** dot color matches the session's run status; row click selects the chat.
- **Edge/error cases:** runs fetch fails → all dots grey/idle (silent catch). Session with no run → grey dot, title "idle".

### UC-C11 · Settings (sidebar entry + footer gear)
- **Preconditions/state:** authenticated.
- **Input:** click `button-settings-sidebar`, then `button-settings` (footer).
- **Action flow:** 1. Click `button-settings-sidebar` ("Settings & API Keys") → `SettingsDialog` opens. 2. Close. 3. Click footer `button-settings` gear → same dialog opens.
- **Expected output:** `SettingsDialog` opens from either control; analytics `settings_opened` tracked.
- **Information flow:** both → `setShowSettingsDialog(true)`.
- **Pass criteria:** settings dialog opens from both entry points.
- **Edge/error cases:** none.

### UC-C12 · Collapse toggle
- **Preconditions/state:** sidebar expanded.
- **Input:** click `button-sidebar-toggle`.
- **Action flow:** 1. Click the collapse button (top-right of the logo header).
- **Expected output:** `onToggleSidebar` fires — desktop collapses the rail to the icon-rail; mobile closes the drawer (App.tsx wiring: desktop `toggleSidebar`, mobile `setMobileMenuOpen(false)`).
- **Information flow:** `onClick={onToggleSidebar}` → parent collapse state.
- **Pass criteria:** sidebar collapses/closes; expand path restores (parent-owned).
- **Edge/error cases:** the icon-rail expand control lives in the parent (`App.tsx`), not this file — verify the round-trip at the App level.

### UC-C13 · Logout
- **Preconditions/state:** authenticated.
- **Input:** click `button-logout`.
- **Action flow:** 1. Click "Sign out".
- **Expected output:** `await logout()` then `setLocation('/login')` → login page.
- **Information flow:** `useAuth().logout` + wouter `setLocation('/login')`.
- **Pass criteria:** session cleared; pathname `/login`.
- **Edge/error cases:** logout rejects → navigation still occurs only after await resolves; verify no half-authenticated state.

### UC-C14 · Recent Tools dialog — instantiated but not toggled here **[SPEC-DRIFT]**
- **Preconditions/state:** authenticated.
- **Input:** search the sidebar for a control that sets `showRecentToolsDialog`.
- **Action flow:** 1. Assert a `RecentToolsDialog` is mounted (line 467) but NO button in `app-sidebar.tsx` calls `setShowRecentToolsDialog(true)`.
- **Expected output:** the "Recent Tools" affordance from the `CLAUDE.md` checklist is NOT reachable from this sidebar; `showRecentToolsDialog` stays false. Flag as a coverage gap / spec drift for the product owner.
- **Information flow:** dialog rendered with `open={showRecentToolsDialog}` (default false); no opener wired in this component.
- **Pass criteria:** documented as unreachable-from-sidebar; test asserts the dialog stays closed (no opener). Do NOT invent a testid.
- **Edge/error cases:** if a future opener is added, add a real UC then.

---

## Test-layer guidance

- **Surface A (Design & Generate):** best covered by **component/unit tests** injecting a fake `GenerateClient` (deterministic `GenerationRun` fixtures) for UC-A05–A17b (re-rank purity UC-A12 is the load-bearing assertion: assert the injected client's call counts do NOT increase on a weight edit). Entry-route UCs (A01–A03) assert the wouter location. `isContradiction`, `classifyRejection`, `reRank`, `rankKey`, `buildOrderSheetCsv` are exported and directly unit-testable. Full-stack E2E only needed to prove `/api/generate` proxy wiring.
- **Surface B (Search & Evidence):** component tests with prop fixtures for UC-B01–B05, B08–B11. **UC-B06/B07 (save-to-notes success/failure) MUST hit the real `POST /api/memory/projects/:id/knowledge`** per the no-mock E2E rule — use the fixture account + a real active project (success) and a not-owned project id (failure/403–404).
- **Surface C (Sidebar):** component tests for click→handler/`setLocation` (UC-C01–C13); status-dot color mapping (UC-C10) is derivable from a `/api/workflows/runs` fixture. Route landings (C04–C07) verifiable at App level. UC-C14 is a documentation assertion.

## Open questions / drift to raise with the owner
1. `CLAUDE.md` sidebar checklist (Runs/CRO Library/Billing/Starred/Recent Tools) is stale vs the shipped `app-sidebar.tsx`. Either the doc or the nav should be reconciled.
2. `answer-make-instruction` is permanently disabled (no write endpoint) — brief expected a working exit.
3. `RecentToolsDialog` is mounted with no opener in the sidebar.
