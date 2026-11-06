# V2 GAP — Cold Start / Composer / Chat vs claude-design v2

**Date:** 2026-09-09
**Scope:** Front-door / composer / chat surfaces of the DEPLOYED BioMate frontend
(`frontend/client/src/`, branch `integration/dev-test`) vs the NEW claude-design
`data_centroid_design_v2`. READ-ONLY audit. No source edited, no commit.

**References**
- NEW v2 spec/prototype: `reference/claude_design/data_centroid_design_v2/`
- OLD (diff baseline): `.../scratchpad/old_design/reference/claude_design/data_centroid_design/`
- Deployed code: `frontend/client/src/`

**Method:** For each heavily-revised v2 surface, diff OLD→v2 to extract the
net-new/changed requirement, then compare each to the deployed code and grade
`DONE` / `PARTIAL` / `UNDONE`. This doc focuses on **net-new v2 requirements**;
requirements that already existed in the old design and were not changed are not
re-litigated here.

> **2026-09-12 interpretation update:** this is retained as point-in-time
> implementation evidence. The accepted product scope now keeps four modules
> but demotes dense modality controls, per-request add-on scope machinery, and
> pane choreography. Read its priorities with
> [`20260912_V2_GAP_REBASE_AFTER_SIMPLIFICATION.md`](20260912_V2_GAP_REBASE_AFTER_SIMPLIFICATION.md).

---

## Coverage checklist (net-new v2 requirements)

| # | v2 surface | Net-new requirement | Status |
|---|---|---|---|
| 1 | Composer | Say the consequence, not the lane (drop lane name; dot only) | PARTIAL |
| 2 | Composer | "why this?" (not "why this lane?") | UNDONE |
| 3 | Composer | Typed clarification card (bound values, inferred pre-select, counter) | PARTIAL — component built, NOT wired |
| 4 | Composer | Post-run reply contract (substantive answer, not "Done.") | UNDONE |
| 5 | Composer | Mid-run narration cadence (phase-boundary lines) | PARTIAL |
| 6 | Composer | Project *suggested* row (file-it-there / keep-unfiled) | UNDONE |
| 7 | Composer | New chat never gated on choosing a project | DONE (never had picker) |
| 8 | Composer | Skills & experts: connected-once / on-per-project / per-request deviate | UNDONE |
| 9 | Cold start | Modality selector (small-molecule / peptide / protein) on Design card | UNDONE |
| 10 | Cold start | Per-example action hint ("ask" / "open") + card lane/ok chips | UNDONE |
| 11 | Cold start | Pre-trained "Run a model" track + INFER routes | PARTIAL |
| 12 | Cold start | Design card retitled to multi-modality; 4th track "Propose & test" | UNDONE |
| 13 | Foundations | Verification is one pattern (§0.13) | DONE |
| 14 | Foundations | Roles & permissions — disabled-not-hidden (§0.14) | DONE |
| 15 | Foundations | Domain viewers / evidence-class resolver rule (§0.7.1) | Out of scope (panel) |
| 16 | Foundations | Every view resizes and hides (§0.11) | PARTIAL |
| 17 | Foundations | Connectors: four sections, one surface (§0.9) | Out of scope (Connectors) |
| 18 | App routing | Search / ModelCase instant surfaces open directly from a seed | UNDONE |
| 19 | App routing | Models surface "earned" per project | Out of scope (Models) |

**Net UNDONE:** 8  ·  **Net PARTIAL:** 6  (of the 14 in-scope net-new items)

---

## Surface 1 — `spec/00 Foundations and the cold start.html` (+159 lines)

### What changed in v2 (highlights)
The old §0.7–§0.10 grew into §0.7–§0.16. Net-new sections:
- **§0.7 Evidence-class resolution rule** — class is resolved *from the output*
  (extension-first, content-sniff fallback), one resolver used by every surface;
  NOT a backend tag. **§0.7.1 Domain viewers** — structure/sequence/screening
  outputs need science-specific viewers, not generic ones.
- **§0.8 Navigation copy** — nav items carry a **label only**; the explanation
  lives on the surface (anchor text), never as a truncated rail subtitle.
- **§0.9 Connectors — four sections, one surface** — data sources / models /
  skills+experts / MCP; "we do not classify add-ons" (declared facts, not
  categories); **§0.9.2 scope** (account = connected, project = on-here, request =
  on-for-this-question); **§0.9.3 residency** (cloud / on-prem / mounted / this-
  machine / prompt-only on every row); preview-before-attach.
- **§0.10 Density, type, data colour** — base 14px, tinted table headers, zebra.
- **§0.11 Every view resizes and hides** — sidebar / file-list / right-panel drag-
  resizable + collapsible; preference vs applied width; collapse is session-only.
- **§0.13 Verification is one pattern** — 5 checks share measured/threshold/verdict.
- **§0.14 Roles & permissions** — Viewer/Contributor/Reviewer/Owner; a control the
  user may not use is **disabled with the role named, never hidden**.

### Gap table

| Element | v2 spec says | Changed-from-old? | Deployed status | Evidence (file:line) | Fill priority |
|---|---|---|---|---|---|
| Verification one pattern (§0.13) | Every gate reads measured · threshold · verdict; human approval is a gate whose measurer is a person | NEW | **DONE** | `nextflow-workflow-viewer.tsx:2982-2990` (`VerifyPattern`, `verifyKinds`); `roles-verify.tsx` `VerifyPattern` | — |
| Human approval uses gate grammar (§0.13) | Same layout as QC gate, not a bespoke dialog | NEW | **DONE** | `nextflow-workflow-viewer.tsx:2699-2704` (approval reads in measured·threshold·verdict grammar) | — |
| Roles disabled-not-hidden (§0.14) | Control the user may not use shown disabled with the role it requires | NEW | **DONE** | `roles-verify.tsx:5` (disabled never hidden), `:55` ("Your permissions here"); wired `nextflow-workflow-viewer.tsx:2971-2989` (`RolesCard`) | — |
| Roles reflect real ownership model | v2 has 4 roles; deployed notes real model is single-owner, project-roles endpoint pending | NEW | **PARTIAL** | `nextflow-workflow-viewer.tsx:2966-2971` (documented follow-up when project-roles endpoint surfaces) | Low (backend dep) |
| Evidence-class resolver rule (§0.7) | One resolver, extension-first + content-sniff, used by every surface | NEW | Out of scope (workflow-panel / output-preview surface, not cold-start/composer/chat) | — | — |
| Domain viewers (§0.7.1) | Structure→3D+confidence chart; sequence→score tracks; screening→2D grid | NEW | Out of scope (panel) | — | — |
| Nav label-only + on-surface anchor text (§0.8) | Rail items carry a label only | NEW | Out of scope (sidebar) — note: deployed sidebar is a separate audit | — | — |
| Every view resizes and hides (§0.11) | Sidebar / file-list / right panel drag-resizable + collapsible | NEW | **PARTIAL** — right workflow panel resizes; sidebar/file-list hide+resize is the reference `Grip`/`Reveal`/`useCollapse` model, deployed only resizes the workflow panel | `chat-with-artifacts.tsx:2305-2315` (panel drag-resize, `minWidth 320/maxWidth 900`); NO `Grip`/`Reveal`/`useCollapse`/`sideHid`/`chatHid` in deployed tree | Medium |

---

## Surface 2 — `spec/06 The composer.html` (+101 lines) & `dataui/ChatView.jsx` (+~90 lines)

### What changed in v2 (highlights)
- **§6.2 Say the consequence, not the lane (NEW rule).** The preview no longer
  prints the lane name ("Instant · compute"). A small **dot** carries instant-vs-
  cloud beside the domain. "why this lane?" becomes **"why this?"**.
- **§6.4 Typed clarification (NEW).** When the extractor makes a low-confidence
  inference, ask with a **confirm-inference card**: one decision per card, a
  step counter (1/2), numbered options, each option carrying **the bound value**
  (`reference_build = GRCh38.p14/ens110`), inferred option pre-selected & badged,
  "None of these — I'll say it in my own words" escape hatch, Skip/Previous/Next.
  An answer selects a schema value or workflow id — never re-parsed as language.
- **§6.6 States → Project suggested (NEW).** A row above the composer proposes a
  home once there is a signal, with *File it there* / *Keep unfiled*.
  **§6.6.1 Filing follows intent** — new chat is **never gated** on choosing a
  project; it opens unfiled, the project is *proposed* from an attachment or the
  goal's words, and unfiled is a legitimate resting state.
- **§6.5 Experts vs skills.** Experts are lenses picked per request; skills are
  invoked by the work. ChatView Composer replaces the hardcoded `PACKS` list with
  a project-driven **"Skills & experts · N on"** popover headed *On in <project>*,
  reading the account library with project choices checked/badged `project`, and a
  per-question deviation marked *changed* — one source (`ACCOUNT_ADDONS` + project
  selection), the composer reads it, never keeps its own list.
- **§6.9 What the assistant says, and when (NEW).** Post-run **reply contract**: a
  1–2 sentence substantive answer ("1,284 genes move at FDR<0.05…"), not "Done.";
  names the caveat; never over-asserts; points at the artifact. **Mid-run
  narration cadence**: one short line at start / phase boundary / gate — never one
  line per step; narration is part of the trajectory record.
- ChatView also gained **reveal/hide chat** buttons in the header (`revealPanel`,
  `onHide`) and a lane-copy source-of-truth table (`LANE_COPY`, `DOM_COPY`) keyed
  by the router lane so the preview can never disagree with the router.

### Gap table

| Element | v2 spec says | Changed-from-old? | Deployed status | Evidence (file:line) | Fill priority |
|---|---|---|---|---|---|
| Say the consequence, not the lane (§6.2) | Drop lane NAME from preview; a dot carries instant-vs-cloud beside the domain | NEW rule | **PARTIAL** — deployed shows a dot **and** still prints the lane label ("Instant · cited answer" / "Cloud · validated workflow") | `lane-preview.tsx:68-69` (`INSTANT_LABEL`/`CLOUD_LABEL`), `:204-215` (dot + `v.label` + sentence) | Medium |
| "why this?" wording (§6.2) | Rename "why this lane?" → "why this?" | NEW | **UNDONE** — deployed has no "why this" affordance at all; only an override underline link | `lane-preview.tsx:221-239` (override link, no "why this?" chip) | Low |
| Lane preview single source keyed by router lane | `LANE_COPY`/`DOM_COPY` per-lane sentences; preview can't disagree with router | NEW | **PARTIAL** — deployed derives label/sentence from server `/api/route/classify` (instant/cloud) with a local heuristic fallback; two-way only, no per-domain `DOM_COPY` sentences | `lane-preview.tsx:139-155` (server classify), `:180-215`; domain read layered in `cold-start-dashboard.tsx:314-383` | Medium |
| Typed clarification card (§6.4) | Confirm-inference card: bound values, inferred pre-select, step counter, own-words escape, Skip/Prev/Next | NEW | **PARTIAL** — `ClarifyCard` component fully built to spec (bound value per option, inferred pick, typed answer) but **NOT wired** into chat render; chat still renders the older `ParamClarificationCard`/`IntentClarificationCard` | `clarify-card.tsx:1-60` (built); `chat-message.tsx:62-63,636-686` (only Param/Intent cards rendered); grep: `ClarifyCard` NOT referenced in chat-message/chat-interface | **High** |
| Options carry bound value (§6.4 binding rule) | Each option shows `field = value` in mono; answering selects a schema value / workflow id | NEW | **PARTIAL** — `ClarifyOption.val` carries it, but unused until card is wired | `clarify-card.tsx:37-47` | High (blocked by wiring) |
| Project suggested row (§6.6) | Row above composer: "This reads like <project> · File it there / Keep unfiled" | NEW | **UNDONE** — no `suggestrow` / "File it there" / "Keep unfiled" / `suggestProj` anywhere in deployed tree | grep across `components/*.tsx` + `App.tsx`: 0 hits | **High** |
| Filing follows intent — never gated on project (§6.6.1) | New chat opens unfiled immediately, no picker | NEW rule (removes old picker) | **DONE** — deployed new-chat has no where-should-this-live picker | No project-picker in `App.tsx`/chat entry (reference removed `picker`/`pickrow`; deployed never had it) | — |
| Skills & experts scope model (§0.9.2 / §6.5) | "Skills & experts · N on" popover, *On in <project>*, project badge, per-question *changed* deviation, one source | NEW | **UNDONE** — no `projectOn` / "On in <project>" / deviation model / "Skills & experts" popover in composer (`chat-input.tsx` has no experts/skills UI at all) | grep `chat-input.tsx`: 0 experts/skills; grep `projectOn`/"skills & experts": 0 hits | **High** |
| Post-run reply contract (§6.9.1) | 1–2 sentence substantive answer after a run; names caveat; points at artifact | NEW | **UNDONE** — no reply-contract enforcement; deployed relies on whatever backend `data.response` returns | `chat-interface.tsx:1064-1069` (only failure-narrative detection); no substantive-reply contract | **High** |
| Mid-run narration cadence (§6.9.2) | One line at start / phase boundary / gate; never per-step; part of trajectory | NEW | **PARTIAL** — deployed surfaces backend "workflow_progress" narrator lines as short italic messages (de-duped), but cadence (per-step suppression, phase-boundary framing) is backend-driven and not enforced client-side | `chat-interface.tsx:731-745` (`handleWorkflowProgress`, italic progress lines) | Medium |
| Reveal/hide chat header buttons | ChatView `revealPanel` / `onHide` / "Hide chat" | NEW | **UNDONE** — deployed has no hide-chat/reveal-panel buttons (single-column chat + resizable panel only) | `chat-with-artifacts.tsx` — no `revealbtn`/"Hide chat" | Low |

---

## Surface 3 — `dataui/ColdStart.jsx` + `dataui/data-part3.js` (+112) → deployed `cold-start-dashboard.tsx`

### What changed in v2 (highlights)
- **Modality selector on the Design card.** `ColdStart.jsx` adds `mod` state and a
  `MODALITIES` chip row (`Small molecule` / `Peptide` / `Protein / biologic`);
  the example list switches per modality via `tr.exBy[mod]`. Seeds carry the
  modality (`onSeed(x, mod)`).
- **Per-example action hint.** Search examples render an `ask` pill, Models
  examples an `open` pill; the card shows an `ok` chip ("answers on click" /
  "opens a worked example") beside the lane chip.
- **Design card retitled + 4th modality.** Title becomes "Propose candidates —
  molecules, peptides, proteins — then optimise and rank them"; tracks renamed
  (`Predict & filter`, `Optimise properties · one pass`) and the Models module
  gains a **"Run a model"** pre-trained track. `data-part3.js` adds
  `window.MODALITIES`, `MOD_WORD`, `modalityOf()`, and **INFER routes**
  (Structure prediction / Sequence scoring / Library screening) plus new domain
  routes (Peptide design, Protein & biologic design, batch correction, SAP check).
- **Self-test hardening** in `data-part3.js`: lane-preview copy is checked against
  the router; connectors residency checked; assertion-throws become findings.

### Gap table

| Element | v2 spec says | Changed-from-old? | Deployed status | Evidence (file:line) | Fill priority |
|---|---|---|---|---|---|
| Modality selector on Design card | `Small molecule` / `Peptide` / `Protein / biologic` chip row; example list switches per modality; seed carries modality | NEW | **UNDONE** — deployed Design card has no modality chips; single small-molecule example list | `cold-start-dashboard.tsx:238-274` (Design track uses old titles/examples, no modality); grep `MODALIT`/`Peptide`/`Small molecule`: 0 hits | **High** |
| Design card retitle | Title = "Propose candidates — molecules, peptides, proteins…" | NEW | **UNDONE** — deployed keeps OLD title "Propose molecules, then optimise and rank them" | `cold-start-dashboard.tsx:238` | Medium |
| Track rename (`Predict & filter`, `Optimise … one pass`) | v2 renamed the design tracks | NEW | **UNDONE** — deployed keeps "Predict activity" / "Optimise properties" (old) | `cold-start-dashboard.tsx:250,258` | Medium |
| 4th track "Propose & test in rounds" (models) / "Run a model" | Models module gains pre-trained single-shot call track | NEW | **PARTIAL** — deployed cold-start has a "Predict and assess a structure" shape (`:110`) and DOMAIN_RULES for Structure prediction / Sequence scoring / Library screening exist, but no dedicated "Run a model" module track mirroring v2 | `cold-start-dashboard.tsx:110`, `:331-334` (INFER-style domain rules present) | Medium |
| Per-example action hint (`ask` / `open`) | Search rows show `ask`, Models rows show `open` | NEW | **UNDONE** — deployed `ExampleRow` has no action pill | `cold-start-dashboard.tsx:509-520` (plain example rows) | Low |
| Card lane + `ok` chips ("answers on click"/"opens a worked example") | Card shows lane chip + ok chip | NEW | **UNDONE** — deployed cards don't render lane/ok chips on the card head | grep `answers on click`/`opens a worked`: 0 hits | Low |
| Seed carries modality | `onSeed(x, mod)` so downstream run opens in that modality | NEW | **UNDONE** — deployed `onSeed(text)` is single-arg | `cold-start-dashboard.tsx:387,510-520` (`onSeed: (text) => void`) | Medium |
| INFER / new domain routes | Peptide design, Protein/biologic design, batch correction, SAP check, structure/sequence/library-screen | NEW | **PARTIAL** — deployed `DOMAIN_RULES` covers structure/sequence/library-screen + drug-discovery, but **no Peptide / Protein-biologic design rules** and no batch-correction/SAP domains | `cold-start-dashboard.tsx:324-350` (rules present); no peptide/protein-design/batch/SAP rules | Medium |

---

## Surface 4 — `dataui/App.jsx` (+157 — new routing) → deployed `App.tsx`

### What changed in v2 (highlights)
- **Seed routing by lane.** `goSeed`/`send` inspect `laneOf(s)`: an `Instant ·
  search` seed opens the **SearchAnswer** surface directly; a `Cloud · models`
  seed with a worked case opens **ModelCase**; otherwise it starts a chat/run.
- **Connectors, Search, ModelCase views** added to the stage router; new-chat
  drops the project picker and opens unfiled.
- **Project suggestion** (`suggestProj`) + one-click **File it there**.
- **Skills & experts per-project state** (`addonsBy` / `setAddon`), fed to the
  composer as `projectOn`.
- **Resize/hide plumbing** — `Grip`/`Reveal`/`useCollapse`, `sideHid`/`chatHid`,
  auto-hide-on-narrow, `hidePanel`/`showPanel`.
- **Models surface "earned" per project** (`earnedMl`, `hasMl`, `mlScope`).

### Gap table

| Element | v2 spec says | Changed-from-old? | Deployed status | Evidence (file:line) | Fill priority |
|---|---|---|---|---|---|
| Seed → SearchAnswer surface directly | Instant-search seed opens the answer surface, not a chat/run | NEW | **UNDONE** — deployed has no search-answer direct-open from a seed | `App.tsx` — no `laneOf`/`goSeed` search branch; `/models` route only (`:654-657`) | Medium |
| Seed → ModelCase surface | Models seed with a worked case opens ModelCase | NEW | **UNDONE** — no ModelCase view in deployed routing | `App.tsx` grep: no `ModelCase`/`mcase` | Low |
| Connectors as a stage view (§0.9) | Connectors 4-section surface routed in the stage | NEW | Out of scope here (Connectors surface) — note deployed has `connectors-dialog.tsx` (a dialog, not the §0.9 4-section surface) | `connectors-dialog.tsx:185` | — |
| Project suggestion + one-click file (App wiring) | `suggestProj` feeds the composer's suggest row; `onFile` sets project | NEW | **UNDONE** — no `suggestProj`/`onFile` wiring | `App.tsx` grep: 0 hits | High (pairs with composer #6) |
| Skills & experts per-project state (App) | `addonsBy`/`setAddon` fed to composer as `projectOn` | NEW | **UNDONE** — no per-project addon state | `App.tsx` grep: 0 hits | High (pairs with composer #8) |
| Resize/hide plumbing (`Grip`/`Reveal`/`useCollapse`) | Sidebar/panel resize + hide with auto-hide-on-narrow | NEW | **PARTIAL** — only the workflow panel drag-resizes; no `Grip`/`Reveal`/`useCollapse`/`sideHid`/`chatHid` | `chat-with-artifacts.tsx:2305-2315` | Medium |
| Models "earned" per project | `earnedMl`/`hasMl` gate the Models surface per project | NEW | Out of scope (Models surface) | `models.tsx` (`ModelsPanel`, `App.tsx:654`) | — |

---

## Priority summary for filling the gaps

**High priority (net-new v2 requirements, in-scope, not started or unwired):**
1. **Wire `ClarifyCard` into chat** (`chat-message.tsx`) — the typed clarification
   component is built to spec but never rendered; §6.4 is the composer's headline
   v2 addition. (composer #3/#4-elem)
2. **Project suggested row + filing** (`ChatView`/`App.tsx`) — §6.6 / §6.6.1;
   nothing deployed. (composer #6, App wiring)
3. **Skills & experts scope model** (`ChatView` composer + `App.tsx` per-project
   state) — §0.9.2 / §6.5; nothing deployed. (composer #8, App wiring)
4. **Post-run reply contract** (§6.9.1) — enforce a substantive 1–2 sentence
   answer instead of a bare status.
5. **Modality selector on the Design cold-start card** (§ ColdStart) — no modality
   chips deployed.

**Medium priority:** drop the lane name from the preview (dot-only, §6.2); add
per-domain `DOM_COPY` sentences; sidebar/file-list resize+hide (§0.11); seed→
SearchAnswer routing; peptide/protein-design + batch/SAP domain routes; Design
card retitle + 4th track.

**Low priority:** "why this?" rename; per-example ask/open pills + card ok chips;
hide-chat/reveal buttons; ModelCase seed routing.

**Already DONE in v2 terms:** Verification one pattern (§0.13, `VerifyPattern`),
Roles disabled-not-hidden (§0.14, `RolesCard`), human-approval-as-gate grammar,
new-chat-never-gated-on-project.

---

## Honesty notes
- "Out of scope" rows are v2 requirements that live on the **workflow panel,
  sidebar, Connectors, or Models** surfaces, which this audit was not asked to
  grade; they are listed so the coverage map is complete, not because they are
  necessarily done.
- Deployed lane preview is **server-driven** (`/api/route/classify`) with a local
  heuristic fallback; the reference prototype is a pure client `window.ROUTES`
  table. They are functionally comparable for the front-door read; the gap graded
  is only the presentational rule (dot-only, "why this?") and the per-domain
  sentence table.
- `ClarifyCard` grading is "PARTIAL, not wired" (not UNDONE) because the component
  exists and is complete; the only missing piece is its render site in chat.
