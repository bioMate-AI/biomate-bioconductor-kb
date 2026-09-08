# Claude-Design Implementation Gap Inventory (master)

**Status: 2026-09-08 — upgrade now broadly IMPLEMENTED on `feat/data-centric-upgrade`.**
The 2026-09-05 audit below described a thin (~25–35%), partly-orphaned slice.
Since then Tier-0/Tier-1/Tier-2 backlog items have been built out on
`feat/data-centric-upgrade`: the dataset centroid object + `/files` hub +
perception-at-ingest + lineage/consumers/versions backend, the four orphaned
panel components mounted (trajectory as the 8th after-run tab, approval-gate,
roles, skip) with a skip-DAG backend feeding real states, the composer two-lane
preview + "Redo as validated run" + ideation-plan, the cold-start module
dashboard + intent router, Design & Generate (Pareto, editable weights,
rejection profile, per-row "why", export order sheet, entry routes,
predicted-vs-measured), Models (5/5 real tracks, objects-not-strings, backend
track endpoints, persisted mutations), the full step-view object (provenance,
param-origin badges, raw/rendered toggle), param-origin badges + findings→output
links, Search & Evidence (source locus, reader pane, conflict row), and
Connectors (residency + scopes + declared facts). ClarifyCard is now wired and
the reference CSS tokens are consumed by the data-centric components.
**Honest floor:** nothing here is E2E-tested on dev yet (pending PR #214 merge +
`sync_to_dev.sh`), and the surfaces whose backend is not yet built render honest
empty states. See §12 "Still open (backend/infra)" for what remains. The
2026-09-05 body is retained verbatim below for provenance; verdicts in the tables
are updated inline with a `→ 2026-09-08:` note.

**Date:** 2026-09-05 (audit) · 2026-09-08 (implementation-status update)
**What this is:** the honest, element-by-element comparison of the built BioMate
data-centric/DL upgrade against the full claude-design reference
(`reference/claude_design/data_centroid_design/` — 9 spec docs `spec 2/00–08` +
the `dataui/*.jsx` prototype). Produced by a 9-way parallel adversarial audit
(read-only) of the merge candidate at `/Users/kky/biomate-review` (wave 1–3 +
bionemo + the code-review fixes).
**Why:** the earlier build was scoped from a summary "spec," not the actual
reference. This traverses the reference itself. Nothing is merged/synced to dev
until this scope is understood.

Legend: ✅ built & faithful · 🟡 partial / mock / **orphaned (built but not wired)** · ❌ absent

---

## 0. Headline

**2026-09-05 (audit):** the upgrade was a thin (~25–35%), partly-orphaned,
partly-re-skinned slice of the design. The *data-centric spine* — the premise of
the whole effort — was essentially unbuilt. Much of what *was* built was not
wired into the product, and the newest components diverged from the reference CSS
that was already ported next to them.

**→ 2026-09-08 (now):** the data-centric spine is **built** on
`feat/data-centric-upgrade`. The dataset centroid object, the `/files` hub,
perception-at-ingest, and the previously orphaned panels are all wired; the
newest components consume the reference CSS tokens. What remains is
backend/infra (arbitration, real versioning + RO-Crate, GPU training on Batch,
full claim→output wiring) and dev E2E verification (§12).

| Reference surface (spec) | 2026-09-05 (audit) | → 2026-09-08 (now) | One-line verdict |
|---|---|---|---|
| Foundations + Search/Evidence (00–01) | ~10% | **BUILT** | cold-start module dashboard + intent router built; Search & Evidence source locus + reader pane + conflict row built; roles built; Connectors residency/scopes/declared-facts built |
| Data analysis + **Dataset object** (02, 04) | ~4% live | **BUILT** | dataset-as-centroid object + `/files` hub + perception-at-ingest + lineage/consumers/versions backend built; "Redo as validated run" built (versioning is honest v1-only, §12) |
| Models (03) | ~22–25% | **BUILT** | 5/5 real tracks + objects-not-strings + backend track endpoints + persisted mutations (GPU training on Batch still open, §12) |
| Design & Generate (05) | ~40% | **BUILT** | Pareto view, editable weights, rejection profile, per-row "why", export order sheet, entry routes, predicted-vs-measured all built |
| DL output viewers (part of 05) | ~85% | **BUILT** | faithful behavior retained; now on reference CSS tokens |
| Composer + Workflow panel + Full step view (06–08) | ~30% | **BUILT** | composer lane preview + "Redo as validated run" + ideation-plan built; full step-view object (provenance, param-origin badges, raw/rendered toggle) built; approval-gate + trajectory (8th tab) + skip mounted with skip-DAG backend feeding real states |
| Gaps / reasoning surfaces | 0% wired | **BUILT** | ClarifyCard wired; trajectory/approval/roles/skip mounted (previously orphaned) |
| CSS / design system | bimodal | **BUILT** | reference CSS tokens now consumed by the data-centric components |
| Sidebar | mostly works | **BUILT** | data-centric nav spine present; fabricated-count mock removed; dead elements resolved |
| Cold-start ability examples | disabled | **BUILT** | cold-start module dashboard + intent router built (per-seed dev executability still gated on §12 E2E) |

---

## 1. The data-centric spine (specs 02 + 04) — the premise, ~0% live

> **→ 2026-09-08: BUILT.** The dataset centroid object now exists for data
> (identity + quality + versions + lineage + consumers + provenance), reachable
> via a `/files` data-hub route. Perception-at-ingest is mounted (Good/Watch/
> Blocked + leakage + effective-N + class balance) and backed by a real backend
> profiler. Lineage/consumers/versions are served from the backend. "Redo as
> validated run" escalation is built. Declared-skip DAG gating is wired end-to-end
> (backend feeds real skip states to the mounted `skip-dependency.tsx`; the
> `rerun-from-step` field is now accepted by `nextflow_executor.py`). **Honest
> floor:** versioning/append-only is a v1 (not the full append-only + RO-Crate
> export — see §12); surfaces whose backend is not yet built render honest empty
> states.

The upgrade's central claim: a file is not an inert blob but a **centroid
object** (identity + quality + versions + lineage + consumers + provenance).
Status: **the dataset object does not exist for data.**

- **No dataset-object component, no `/files` or data-hub route.** `project-file-tree.tsx`
  treats files as inert (size + preview only; no quality dot, no version tag, no
  click-through to an object). The centroid pattern *is* built faithfully — but
  **only for Models** (`components/models/model-object.tsx`); it was never applied
  to data. The template exists; it was pointed at the wrong noun.
- **"Redo as validated run"** (spec §2.2, *"the single most important path in the
  module"*) — entirely absent. No lane chip, no compute-result card, no escalation.
- **Version history / append-only** ("a completed run keeps the exact bytes it
  consumed") — absent. No versioning at all → the audit-trail guarantee is unmet.
- **Lineage / consumers / "runs that read this file" per version** — absent.
- **Perception-at-ingest** — `data-perception.tsx` implements Good/Watch/Blocked +
  leakage + effective-N + class balance + "how it shaped the plan," but is
  **orphaned (never rendered)** and its backend profiler does not exist on this
  branch. (A backend profiler `data_perception.py` *was* built on
  `feat/data-perception-profiler` but was never pushed/merged.)
- **Declared-skip DAG gating** (§2.5) — all three states fully coded in the
  orphaned `skip-dependency.tsx`, never mounted, no backend. `step-adjust-modal.tsx`
  POSTs `rerun-from-step` to a backend that **drops the field** (`nextflow_executor.py`
  has no such param) — a dead wire.
- **Evidence-class taxonomy** (perceptual/quantitative/symbolic/procedural) +
  **raw⇄rendered toggle** — absent. The build's "evidence class" is an unrelated
  3-domain (structure/genomic/chemical) model-viewer dispatch.
- **Origin / scope / content-hash / dedup / RO-Crate export** — absent.

Score: ~70 elements specified, **3 fully implemented**, ~22 partial-or-orphaned, ~45 absent.

---

## 2. Foundations + Search & Evidence (specs 00–01) — ~10%

> **→ 2026-09-08: BUILT.** Cold-start module dashboard + intent router built.
> Search & Evidence answer anatomy now carries source **locus**, a **reader
> pane**, and a **conflict row**. Roles/permissions built. Connectors residency +
> scopes + declared facts built. The fabricated `toolCategories` counts
> (no-inventory violation) are removed. The `data_sources.py` "one source
> registry" is now surfaced to the frontend.

- **Cold-start module dashboard + intent-router UI** (§0.4, §0.5) — ❌. Users land
  on a chat box; `ReturningUserWelcome` returns `null`. No module grid, no track
  tabs, no route-box (lane/domain/Start).
- **Two-lane model (Instant/Cloud), stated before work** (§0.3, §0.15.3) — ❌. The
  spec's core honesty mechanism is never shown to the client.
- **Search & Evidence answer anatomy** (§1.3): lane+corpora chip, conflict row,
  source **locus** citation, source reader pane, save-to-notes, make-instruction,
  recency/corpus-version, anti-confabulation labelling — all ❌ or 🟡. Citations
  render as `[[N]]` links with no locus.
- **Rules actively violated:**
  - **No-inventory rule (§0.15.1):** `app-sidebar.tsx:65-110` hardcodes fabricated
    counts `45 / 28 / 32 / 15` (dead `toolCategories` mock).
  - **Anchor-text rule (§0.8):** rail subtitles ("Databases, LLMs & platform
    integrations", etc.) are exactly the failure the spec names.
- **Roles/permissions (§0.14), Connectors residency/scopes (§0.9)** — ❌.
- Backend bright spot: `data_sources.py` is the "one source registry" the spec
  wants — but it is **not surfaced** in any frontend, lacks a Patents category and
  an Internal track.

Score: ~66 audited, ~7 full, ~13 partial, ~46 absent.

---

## 3. Composer + Workflow panel + Full step view (specs 06–08) — ~30%

> **→ 2026-09-08: BUILT.** Composer **lane preview** built (the user is told what
> will happen before sending), plus "Redo as validated run" and the
> **ideation-plan**. **Full step view as an object** built: provenance row,
> resolved-params-with-origin badges, rendered/raw toggle. **Human approval gate**
> and **agent trajectory (8th after-run tab)** are now mounted, as is the **skip**
> affordance (backed by the skip-DAG backend). **Param-origin badges** (default/
> inherited/confirmed/edited) built; **findings→output links** built. **Honest
> floor:** full claim→source wiring is scaffolded (not yet complete — §12); the
> two-lane *arbitration* backend remains open (§12).

- **Lane preview (§6.2 — the spec's "single most consequential element")** — ❌.
  The composer cannot tell the user what will happen before they send.
- **Full step view as an object (Spec 08)** — ❌ as an object; fragmented across an
  output-preview modal + an adjust modal. No provenance row, no
  resolved-params-with-origin badges, no rendered/raw toggle, no claim→source
  linking, no step traversal. **Bright spot:** the evidence-typed output viewers
  (`step-output-preview.tsx`) are strong and near-complete.
- **Human approval gate (§7.6)** — ❌ wired (`approval-gate.tsx` built, unmounted).
  No "Awaiting approval" state.
- **Agent trajectory (§7.7)** — ❌ wired (`trajectory-view.tsx` built, unmounted).
  No 8th after-run tab.
- **Auto-loop QC panel (§7.2) + skip affordances (§7.2, §8.8)** — deliberately
  **commented out** ("until QC loop stable" / "no backend API"), contradicting the
  spec's "on by default, always visible."
- **Parameter origin taxonomy (§7.4, §8.4)** — only "AI-recommended"; no
  default/inherited/confirmed/edited badges.
- **Findings-as-links / number→source (§7.8, §8.6)** — static prose; the
  "auditable by clicking" promise is unmet.
- **Filing-follows-intent (§6.6.1), cross-lane handoff (§6.7), mapping card (§6.8)** — ❌.
- **Built & solid here:** inline QC gate two-number display + apply/keep/cancel,
  QC threshold editor, QC audit tab, 7 after-run tabs, download report, real-time
  SSE status, primary-action states (Confirm/Run again/Restart/Resume), evidence-
  typed viewers, mid-run SSE narration.

Score: ~95 items, ~28 full, ~20 partial, ~47 absent.

**CLAUDE.md UX-standard workflow-panel items unmet:** missing-required
blocked-alert-with-both-buttons; QC-gate-row "Edit"→scroll-to-metric; unified
"Edit params" GlobalParamsPanel; auto-loop remediation was→now diff panel
(commented out).

---

## 4. Models (spec 03) — ~22–25%

> **→ 2026-09-08: BUILT.** All **5/5 tracks are real** (Train/Adapt/Optimise no
> longer placeholder cards), backed by real **backend track endpoints** with
> **persisted mutations**. Model Object follows the **objects-not-strings**
> discipline (lineage/consumers/versions are clickable objects, not bare strings).
> **Honest floor:** GPU training on Batch is **not** built — retrain runs as a CPU
> `prompt_rules` path (§12).

- 5 tracks present as tabs, but **Train / Adapt / Optimise are placeholder cards**
  (static bullet lists). Train run-list + TrainConfig, Adapt cost-ladder + edit-pair
  diff/toggle, and the **entire wet-lab loop `WetLabRound` (§3.7, the flagship
  differentiator) are 0% built.**
- **Registry** ~50% (table present, wrong columns; §3.4/§3.5 side panels + "Plug in
  a model" button missing). **Run-a-pre-trained-model + §3.8 viewers** ~70% (real
  API wiring; 3D is a placeholder, 2D depiction is a placeholder, linked
  pLDDT↔3D selection impossible).
- **Model Object** ~40%: all 5 tabs are shells; lineage/consumers/versions degraded
  from clickable objects to bare strings; no Supersede / Use-in-a-run; no interface
  signature; no version compare. Breaks the spec's "objects, not strings" discipline.

---

## 5. Design & Generate (spec 05) — ~40% (viewers ~85%)

> **→ 2026-09-08: BUILT.** The **Pareto/trade-off view**, the **criteria strip
> with editable weights**, per-row **"why?" rationale**, the **validity-gate
> rejection profile by cause**, the **entry routes**, **predicted-vs-measured**,
> and **export (order sheet)** are all built. Viewers remain faithful and now use
> reference CSS tokens.

- **Present & solid:** constraints-as-interface, no-composite-score, safety-as-gate,
  rejected-stays-visible, two-views (table⇄depictions), cost-before-run.
- **Absent:** the **Pareto/trade-off view** (`pareto` data arrives, never rendered),
  the **criteria strip with editable weights**, per-row **"why?" rationale**, the
  **validity-gate rejection profile by cause**, all **five entry routes**, the entire
  **wet-lab loop + predicted-vs-measured**, and **export (order sheet)**. 4 of 6
  failure states unhandled.
- **Viewers (~85%):** all 4 built and faithful in behavior (SeqTracks + HitGrid are
  actually improvements after the review fixes). Gaps: `PretrainedTab` run-composer
  half not ported; "read this heatmap" explainer missing; systematic palette/chrome
  divergence.

---

## 6. Gaps / reasoning surfaces — 7 built, **0 wired**

> **→ 2026-09-08: BUILT / wired.** The previously orphaned components are now
> mounted into the product: `approval-gate`, `trajectory-view` (8th after-run
> tab), `roles-verify`, `skip-dependency` (with skip-DAG backend), and
> `data-perception` (at ingest). **`ClarifyCard` is now the wired clarify path**
> (it is no longer dead-lettered behind `ParamClarificationCard`). `ideation-plan`
> is wired into the composer.

`clarify-card`, `approval-gate`, `trajectory-view`, `roles-verify`,
`skip-dependency`, `data-perception`, `ideation-plan` are all faithful, typed,
tested components — and **every one is an orphan** (imported only by its own test +
fixtures; grep finds zero product importers). Notable:
- The `ClarifyCard` fixed in the code-review pass (F1) is **dead-lettered behind its
  predecessor** `ParamClarificationCard`, which is the one actually wired into chat.
- `clarify-workflow-resolved` (the deferred L4 item) has **no listener** anywhere.

---

## 7. CSS / design system — **bimodal**

> **→ 2026-09-08: BUILT.** The reference `:root` tokens + semantic classes are now
> **consumed by the data-centric components** (the previously-diverged shadcn/
> Tailwind "System B" surfaces — Models, hit-grid, seq-tracks, clarify-card — pull
> the reference blue accent, density, and semantic classes incl. the
> `.file-chip`/`.fc-q` dataset-as-object quality-dot metaphor). Global
> `index.css`/tailwind left untouched so dashboard/billing/CRO don't regress.

Two design systems coexist:
- **System A (faithful):** the reference `:root` tokens + semantic classes
  (`.chip/.dot/.step/.gate`, cool-blue `--accent`, Inter, JetBrains Mono, 5-step
  radius) are **ported near-verbatim** in `v2/tokens.css`, `styles/workflow-panel.css`,
  `styles/reference-design.css` — scoped under `[data-v2-ui]`/`.wf-panel`. The
  workflow-panel surface is visually faithful.
- **System B (diverged):** the **new data-centric components** (Models, hit-grid,
  seq-tracks, clarify-card) were built in **shadcn/Tailwind** — teal/green accent
  vs the reference's blue, 15px vs 14px density, hardcoded hex verdict colors,
  `Badge`/`Tabs` instead of `.chip`/`.trackbar`. The signature `.file-chip`/`.fc-q`
  "dataset-as-object with a quality dot" metaphor is entirely absent.

**Fix is NOT a re-theme:** (1) unlock the already-ported tokens beyond `[data-v2-ui]`,
(2) port ~6 missing semantic classes (`.file-chip/.fc-q`, `.node`, `.trow/.tdot`,
`.trackb`, `.gate`, `.card2`), (3) swap ~4 component files off shadcn onto them.
Leave global `index.css`/tailwind untouched so dashboard/billing/CRO don't regress.

---

## 8. Sidebar

> **→ 2026-09-08: BUILT.** The `toolCategories` fabricated-count mock is removed
> (no-inventory rule now honoured); the dead sidebar Actions block and decorative
> no-`onClick` icons are resolved; the **data-centric nav spine** (DataHub/Files
> surface + data rail) is present. Stale sidebar e2e testids remain to be
> reconciled during dev E2E (§12).

Live sidebar mostly works (22 elements resolve to real handlers/routes). Defects:
- **8 dead elements:** 2 decorative collapsed-rail icons with no `onClick`
  (App.tsx:480,483); a commented-out Actions block (Starred/Recent Tools/Billing/
  Settings-dup, app-sidebar.tsx:503-522) — `setShowStarredDialog` is **never
  declared** (un-commenting = compile error), `StarredWorkflowsDialog` isn't
  imported, `RecentToolsDialog` is mounted with no trigger.
- **`toolCategories` mock** (65-110): dead code with fabricated `45/28/32/15` counts
  (no-inventory violation). Recommend deletion.
- **Data-centric nav spine missing:** no DataHub/Files surface, no data rail, no
  per-project Instructions/Runs/Models "earning," sessions flat-global not nested.
- **e2e tests stale:** `sidebar-all-buttons.e2e.ts` / `sidebar-trust-matrix.e2e.ts`
  assert removed testids (`button-workspaces-nav`, `button-cro-compliance`,
  `button-capabilities`, `button-blog`, `button-runs-nav`); no vitest coverage. tsc clean.

---

## 9. Cold-start ability executability (the advertised abilities)

> **→ 2026-09-08: dashboard + router BUILT; per-seed executability still gated.**
> The cold-start module dashboard + intent router are built. Per-seed end-to-end
> executability (the ✅/❌/🟡/❓ breakdown below) is **not yet re-verified** — it is
> gated on dev E2E (§12); until then the honest defaults (disabled seeds / empty
> states) stand rather than advertising unverified abilities.

The 32 seed prompts (`WELCOME_PROMPTS`) are **disabled** (`ReturningUserWelcome`
returns `null`) precisely because "the hardcoded suggested queries haven't been
E2E-validated." Tracing each:
- ✅ **8 executable (25%)** — only 2 in the verified `passed_workflows.txt` (ADMET,
  docking). Drug discovery (4/4) + structural biology (3/4) carry the demo.
- ❌ **6 dead (19%)** — incl. **#19 multiome ATAC+RNA emits `random.gauss()`
  fabricated numbers** (a workflow that "succeeds" with fake data — honesty
  violation), #11 helical raises `RuntimeError` by default, #14 Visium `exec_error`,
  #16 no ONT workflow, #22 no phospho workflow.
- 🟡 **9 partial/wrong-scope (28%)** — DIA-NN not actually run, "AlphaFold2"→AF3,
  PPI = STRINGdb lookup, no standalone aligner.
- ❓ **9 need dev verification (28%)** — whole epigenomics domain + half of
  transcriptomics/single-cell, all gated on whether the resolver picks the real
  nf-core download vs a **param stub that fails at runtime** — which is exactly what
  branch `fix/resolver-prefer-real-nfcore-pipeline` is about.

**No `checkRoutes()` self-test** exists (the reference has one asserting every seed
routes to its module). Recommended guard: run each seed through
`generate_workflow_unified` and assert its `nextflow_path` resolves to a real
container-backed file in `passed_workflows.txt`.

---

## 10. Prioritized backlog (biggest first)

**Tier 0 — make what's built honest & wired (small, high-leverage):**
1. Delete the `toolCategories` fabricated-count mock; remove the dead sidebar Actions
   block; fix stale sidebar e2e testids. (no-inventory violation + dead code)
2. Wire the 7 orphaned gap components OR remove them; at minimum replace
   `ParamClarificationCard` with the richer `clarify-card` and add the
   `clarify-workflow-resolved` listener.
3. CSS scope-unlock + ~6-class port + 4-file swap so the new components inherit the
   already-ported reference visual language (incl. the `.file-chip`/`.fc-q` dataset chip).
4. Add the `checkRoutes()` executability self-test; **do not re-enable the cold-start
   seed list** until each seed passes it. Fix/flag the fabricated-output workflow (#19).
5. Fix the `rerun-from-step` dead wire (`nextflow_executor.py` must accept the field).

**Tier 1 — the data-centric spine (the premise):**
6. Build the **dataset object** for data (reuse the `model-object.tsx` template):
   identity + quality + versions + lineage + consumers + origin. Add the `/files`
   data-hub route + data rail. This is the heart of the upgrade.
7. Push/merge the `data_perception.py` backend profiler and **mount** `data-perception.tsx`
   at ingest (quality card before run).
8. "Redo as validated run" escalation + the two-lane preview in the composer.
9. Declared-skip DAG gating end-to-end (backend + mount `skip-dependency.tsx`).

**Tier 2 — surface completeness:**
10. Full step view as an object (provenance row, resolved-params-with-origin badges,
    rendered/raw toggle, claim→source linking, step traversal).
11. Models: Train/Adapt/Optimise real tracks + the wet-lab loop; Model Object
    objects-not-strings.
12. Design & Generate: Pareto view, editable weights, rejection profile, entry routes.
13. Cold-start module dashboard + intent router; Search & Evidence answer anatomy +
    source reader; roles/permissions; Connectors residency/scopes.

---

## 11. Honesty contract / provenance

- Verdicts are from a 9-way read-only audit of `/Users/kky/biomate-review`
  (2026-09-05). Local caveat: the real 328 MB `galaxy_ai_tools.db` and the
  `nf-core-workflows/` downloads are dev-only, so every routing/indexing claim and
  every stub-vs-real resolution carries a **needs-dev-verification** floor
  (the 9 ❓ executability verdicts especially).
- "% built" figures are element-weighted estimates, not precise. The consistent
  signal across all 9 audits is the important part: **thin, partly-orphaned,
  partly-re-skinned; the data-centric spine is unbuilt.**
- The code-review fixes (B1–B5, F1–F3) folded into PR #211 remain valid and tested;
  they fix real runtime bugs in the slice that exists. They do not change this scope
  picture.
- **2026-09-08 update provenance:** the "→ 2026-09-08: BUILT" verdicts describe code
  present on `feat/data-centric-upgrade`. They are **implementation-present, not
  dev-verified** — see §12. The 2026-09-05 audit body above is retained verbatim as
  the baseline the update is measured against.

---

## 12. Still open (backend/infra) — 2026-09-08

The frontend/surface work is broadly built, but the following **backend/infra**
items remain open. Every surface that depends on an unbuilt backend renders an
**honest empty state** (never fabricated data):

- **Two-lane *arbitration* backend.** The lane *preview* (what-will-happen) is
  built; the backend that actually *arbitrates* Instant vs Cloud execution and
  reconciles their results is **not** built.
- **Dataset *versioning* / append-only + RO-Crate.** The dataset object exposes
  versions, but versioning is an **honest v1 only** — not the full append-only
  "a completed run keeps the exact bytes it consumed" guarantee, and RO-Crate
  export is not built.
- **GPU training on Batch.** The Models "retrain" path runs as a **CPU
  `prompt_rules`** path, not real GPU training on AWS Batch.
- **Full claim→output wiring.** Findings→output links exist and the claim→source
  linking is **scaffolded**, but the complete "every number is auditable by
  clicking through to its source" wiring is not finished.

**Not E2E-tested on dev yet.** None of the 2026-09-08 work has been exercised on
dev. It is **pending PR #214 merge + `scripts/sync_to_dev.sh`**. Until then, the
per-seed cold-start executability (§9) and the sidebar e2e testids (§8) are
unreconciled, and all "BUILT" verdicts are implementation-present rather than
dev-verified.

---

## Change log

- **2026-09-05** — initial 9-way read-only audit; scope = thin (~25–35%),
  partly-orphaned, data-centric spine unbuilt.
- **2026-09-08** — updated statuses to reflect the data-centric upgrade now
  broadly IMPLEMENTED on `feat/data-centric-upgrade` (dataset object + `/files`
  hub + perception + lineage/consumers/versions, mounted panels + skip-DAG
  backend, composer lane preview + redo-as-validated + ideation-plan, cold-start
  dashboard + intent router, Design & Generate full, Models 5/5 real + backend +
  persisted mutations, full step-view object, param-origin badges +
  findings→output links, Search & Evidence locus/reader/conflict, Connectors
  residency/scopes/facts, ClarifyCard wired, reference CSS tokens consumed).
  Added §12 "Still open (backend/infra)": arbitration backend, versioning v1 +
  RO-Crate, GPU training on Batch, full claim→output wiring; noted nothing is
  E2E-tested on dev yet (pending PR #214 merge + sync) and that unbuilt-backend
  surfaces render honest empty states. Honesty-contract section preserved.
