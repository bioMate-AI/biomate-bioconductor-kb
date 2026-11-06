# Test Plan — Cold-start, Composer & Chat-message Surfaces

**Date:** 2026-09-09
**Branch:** `integration/dev-test` (workspace `/Users/kky/biomate-review`)
**Author:** grounded read of the live components (no invented testids/routes/states)

## Scope & source files

| Surface | Component | Purpose |
|---|---|---|
| Cold-start dashboard | `frontend/client/src/components/cold-start-dashboard.tsx` | Fresh-session "what can I do here?" — intent bar (routes a described goal to a lane + domain) + 4 function-module cards (Search & evidence, Data analysis, Design & generate, Models), each with track tabs, domain chips (Data analysis only), example rows and workflow-shape rows. All controls SEED the composer; none send. |
| Composer | `frontend/client/src/components/chat-input.tsx` | The message composer: auto-grow textarea (Enter/Shift+Enter), advisory LanePreview + lane override, attach (paperclip local file picker + dataset browser + drag-drop), attached-file/dataset chips + local preview dialog, dataset-cap indicator, send/stop. |
| Lane preview | `frontend/client/src/components/lane-preview.tsx` | Advisory Instant/Cloud verdict strip above the composer: local heuristic (`laneForText`) shown immediately, upgraded by server arbiter (`POST /api/route/classify`) when it answers; override affordance. |
| Chat message | `frontend/client/src/components/chat-message.tsx` | Renders a single message: user bubble (with attachment chips), AI markdown/code/citations, workflow card / wf-chip / disambiguation / pipeline / chain cards, progress fold line + WhyAnchor, clarification cards, IND handoff, action row incl. "Redo as a validated run". |

Wiring context (read, not under test here):
- `chat-interface.tsx:2087` renders `<ColdStartDashboard onSeed={…}>` only when `displayMessages.length === 0 && !isTyping && !isTypingLocal`. `onSeed` calls `localSetDraftRef.current(text)` (pre-fills composer) or falls back to `handleSendOrQueue(text)`.
- `chat-input.tsx` exposes `onRegisterSetDraft` — the setter that the dashboard's `onSeed` drives. It calls `setMessage(draft)` then focuses the textarea.
- `/api/route/classify` is proxied at `frontend/server/routes.ts:4896` (`app.all("/api/route/*", optionalAuth, _dlProxyHandler)`) → backend `ai_assistant.py route_classify`; returns `{ lane, domain, why, intent, confidence }`.

---

## Coverage checklist

| Surface | Section | # use cases |
|---|---|---|
| Cold-start dashboard | §1 | 20 |
| Composer (chat-input) | §2 | 18 |
| Lane preview | §3 | 9 |
| Chat message | §4 | 21 |
| **Total** | | **68** |

Legend for the per-UC template:
- **Preconditions / state** — the app/component state before the flow.
- **Input** — user-provided values + required system/app state.
- **Action flow** — numbered user steps.
- **Expected output** — real `data-testid`s + visible copy taken from the code.
- **Information flow** — data source → transform → destination (endpoint / prop / SSE).
- **Pass criteria** — observable, unambiguous.
- **Edge / error cases**.

---

## §1 — Cold-start dashboard (`cold-start-dashboard.tsx`)

**Root:** `data-testid="cold-start-dashboard"`. Heading text: **"What are you trying to do?"** (18px, weight 600). Below it: `IntentBar`, then a responsive grid (`repeat(auto-fit, minmax(300px, 1fr))`) of the four `COLD_MODULES` cards. Only the dashboard state (`openId`) is lifted; each card owns local track (`ti`) + domain (`domId`) state that resets on remount.

### UC-CS-01 — Dashboard renders in a fresh empty session
- **Preconditions / state:** New chat session, zero messages, not streaming.
- **Input:** Load the chat interface with no messages.
- **Action flow:** 1. Open a new chat.
- **Expected output:** `cold-start-dashboard` visible; heading "What are you trying to do?"; `cold-intent-bar` present; exactly 4 `cold-module-card` elements with `data-module-id` in {`search`,`analysis`,`design`,`models`}, each `data-open="false"`; each card header (`cold-module-expand`) shows its `k` title and `t` subtitle: Search & evidence / "A cited answer over literature, databases and patents"; Data analysis / "Work on your own data — ad-hoc or a validated workflow"; Design & generate / "Propose molecules, then optimise and rank them"; Models / "Train, adapt or optimise a model on your data".
- **Information flow:** `chat-interface.tsx` conditionally mounts `ColdStartDashboard` when `displayMessages.length === 0 && !isTyping && !isTypingLocal`. `COLD_MODULES` static array → 4 `ModuleCard`s.
- **Pass criteria:** 4 cards, all collapsed, correct titles/subtitles; heading present.
- **Edge / error cases:** Dashboard MUST NOT render once a message exists or while typing (dismount condition). No inventory numbers/counts anywhere on cards (honesty rule — assert no digit-count strings in card bodies).

### UC-CS-02 — Intent bar idle (no verdict below 7 chars)
- **Preconditions / state:** Dashboard mounted, `cold-intent-input` empty.
- **Input:** Type "herg" (4 chars).
- **Action flow:** 1. Focus `cold-intent-input`. 2. Type "herg".
- **Expected output:** `cold-intent-route` is NOT rendered; `cold-intent-send` present but `disabled` is false only when trimmed length > 0 (so with "herg" it's enabled), yet the route strip stays hidden. Placeholder before typing: "Describe the goal — e.g. screen these molecules for hERG, then rank by developability".
- **Information flow:** `readIntent(q)` returns `null` when `t.length <= 6` → no route strip.
- **Pass criteria:** No `cold-intent-route` for ≤6-char input; send button enabled once any non-space char is present.
- **Edge / error cases:** Whitespace-only input → `canSend=false` (send disabled, opacity 0.4). Exactly 7 chars is the first length that can produce a verdict.

### UC-CS-03 — Intent bar routes an Instant/evidence goal
- **Preconditions / state:** Dashboard mounted.
- **Input:** Type "What is the evidence linking this target to disease?"
- **Action flow:** 1. Type the sentence into `cold-intent-input`.
- **Expected output:** `cold-intent-route` appears with `data-lane="instant"`; `cold-intent-route-lane` reads "Instant · cited answer"; the lane dot is green (`--bm-ok`); `cold-intent-route-domain` chip reads "Literature".
- **Information flow:** `readIntent` → `laneForText` (coarse) + `DOMAIN_RULES` scan. The evidence rule `/(evidence|literature|…)/i` matches → `{ dom:"Literature", lane:"instant" }`; matched domain owns the lane.
- **Pass criteria:** `data-lane="instant"`, lane label "Instant · cited answer", domain chip "Literature".
- **Edge / error cases:** Rule ordering — evidence rules are checked before topic keywords, so a topic word inside a "what is known" question stays Instant.

### UC-CS-04 — Intent bar routes a Cloud/ADMET goal
- **Preconditions / state:** Dashboard mounted.
- **Input:** Type "Screen these SMILES for ADMET liabilities and rank them."
- **Action flow:** 1. Type the sentence.
- **Expected output:** `cold-intent-route` with `data-lane="cloud"`; `cold-intent-route-lane` reads "Cloud · validated workflow" (or lane-preview's own cloud label if it agrees); dot is primary (purple); `cold-intent-route-domain` chip reads "Drug discovery".
- **Information flow:** `DOMAIN_RULES` `/(herg|admet|smiles|liabilit|…)/i` matches → `{dom:"Drug discovery", lane:"cloud"}`. `laneLabel` = coarse label if lanes agree, else fixed "Cloud · validated workflow".
- **Pass criteria:** `data-lane="cloud"`, domain chip "Drug discovery".
- **Edge / error cases:** ADMET rule is intentionally placed BEFORE the ranking rule — "rank" in the same sentence must not steal the domain.

### UC-CS-05 — Intent bar domain read for each DOMAIN_RULES branch
- **Preconditions / state:** Dashboard mounted.
- **Input:** One representative sentence per rule (table below).
- **Action flow:** For each row, clear the input, type the sentence, read `cold-intent-route-domain` + `data-lane`.
- **Expected output (domain chip → lane):**
  - "Who holds composition-of-matter claims on this scaffold?" → Patents / instant
  - "Have we assayed this scaffold before?" → Internal record / instant
  - "Pull every reported structure for this target." → Databases / instant
  - "Why do inhibitors of this target fail on selectivity? cite it" → Literature / instant
  - "Predict the structure for this sequence." → Structure prediction / cloud
  - "Score this locus with a sequence model." → Sequence scoring / cloud
  - "Screen this library for predicted hits." → Library screening / cloud
  - "Fine-tune this property predictor." → Models & training / cloud
  - "Optimise this series without losing solubility." → Property optimisation / cloud
  - "Generate candidates for this target." → Molecular design / cloud
  - "Predict binding affinity for these candidates." → Activity prediction / cloud
  - "Screen these SMILES for hERG." → Drug discovery / cloud
  - "Rank these candidates for developability, top 20." → Candidate ranking / cloud
  - "Quantify differential protein abundance." → (see note) — `proteom` rule = Proteomics / cloud
  - "Compare cell-type composition across single-cell samples." → Transcriptomics / cloud
  - "Differential expression, then GO enrichment." → Transcriptomics / cloud
  - "Call variants on these samples." → Genomics / cloud
  - "Process this cryo-EM set to a density map." → Structural biology / cloud
  - "Stratify this cohort by response, primary endpoint." → Clinical / cloud
  - "Assess run-to-run quality across this batch." → Assay quality / cloud
  - "Plot potency against logP for this table." → Data analysis / instant
- **Information flow:** First-match wins in `DOMAIN_RULES` order; the matched rule's `lane` overrides the coarse lane.
- **Pass criteria:** Each sentence yields the mapped domain chip + lane.
- **Edge / error cases:** No domain match → `cold-intent-route-domain` is absent and lane = coarse `laneForText` read. Order-sensitive collisions (differential-abundance regex matches proteom-first sentence only if `proteom` absent).

### UC-CS-06 — Seed composer via intent-bar send button
- **Preconditions / state:** Dashboard mounted, composer registered `setDraft`.
- **Input:** Type "Call variants on these samples. Human GRCh38."
- **Action flow:** 1. Type the goal. 2. Click `cold-intent-send`.
- **Expected output:** `onSeed(q.trim())` fires → composer textarea (`chat-input`) is pre-filled with the trimmed text and focused; message is NOT sent (no new user bubble).
- **Information flow:** `IntentBar` local `q` → `onSeed` prop → `chat-interface` `localSetDraftRef.current(text)` → `chat-input` `setMessage(draft)` + focus.
- **Pass criteria:** Composer value equals the goal; no message posted; textarea focused.
- **Edge / error cases:** Send button disabled when `q.trim()` empty (`canSend=false`, cursor default, opacity 0.4). If no draft setter registered, `onSeed` falls back to `handleSendOrQueue` (would send) — verify setter is registered before asserting seed-not-send.

### UC-CS-07 — Seed composer via Enter in intent bar
- **Preconditions / state:** Dashboard mounted.
- **Input:** "Differential expression between treated and control, then GO enrichment."
- **Action flow:** 1. Type the goal. 2. Press Enter inside `cold-intent-input`.
- **Expected output:** Same as UC-CS-06 — composer seeded, not sent (`onKeyDown` calls `onSeed(q.trim())` when `q.trim()` truthy).
- **Information flow:** `onKeyDown` Enter branch → `onSeed`.
- **Pass criteria:** Composer seeded on Enter.
- **Edge / error cases:** Enter with empty/whitespace-only `q` → no-op (guarded by `q.trim()`).

### UC-CS-08 — Expand a module card (single-open)
- **Preconditions / state:** All cards collapsed (`openId === null`).
- **Input:** Click Search & evidence header.
- **Action flow:** 1. Click `cold-module-expand` inside `data-module-id="search"`.
- **Expected output:** That card `data-open="true"`, `aria-expanded=true`, chevron becomes ChevronDown; `cold-module-body` renders; card spans full grid width (`gridColumn: "1 / -1"`); a `role="tablist"` with `aria-label="Search & evidence tracks"` shows track tabs.
- **Information flow:** `onToggle` → dashboard `setOpenId(cur => cur===id ? null : id)`.
- **Pass criteria:** Only the clicked card is open; `data-open` toggles; body appears.
- **Edge / error cases:** Opening a second card auto-closes the first (single-open). Re-clicking the open card's header collapses it (`openId` back to null).

### UC-CS-09 — Only one module card open at a time
- **Preconditions / state:** Search & evidence card open.
- **Input:** Click Data analysis header.
- **Action flow:** 1. Open `search`. 2. Open `analysis`.
- **Expected output:** `search` card `data-open="false"`, `analysis` card `data-open="true"`. Exactly one `cold-module-body` in the DOM.
- **Information flow:** `openId` is a single string; `setOpenId(id)` replaces previous.
- **Pass criteria:** At most one open card at any time.
- **Edge / error cases:** Track/domain selection resets when a card is re-opened (local state remounts because tabs render only while open).

### UC-CS-10 — Track tabs render + select (Search & evidence)
- **Preconditions / state:** Search & evidence open.
- **Input:** None (default), then click each track.
- **Action flow:** 1. Open `search`. 2. Read tabs. 3. Click "Databases".
- **Expected output:** Four tabs `cold-track-literature`, `cold-track-databases`, `cold-track-patents`, `cold-track-internal` with visible labels Literature · Databases · Patents · Internal. First tab (Literature) selected on open (`aria-selected=true`, primary fill). After clicking Databases: `cold-track-databases` `aria-selected=true`; example rows swap to that track's `ex` (3 items: "Pull every reported structure for this target.", "Known off-targets for this chemotype?", "Which trials targeted this pathway, and what were their endpoints?").
- **Information flow:** `ModuleCard` local `ti` state; `track = m.tracks[ti]`; `track.ex` → `ExampleRow`s.
- **Pass criteria:** Tab testids correct; selected tab styled; example rows reflect the active track.
- **Edge / error cases:** Switching a track calls `setDomId(null)` — clears any selected domain (only relevant on the Data analysis card).

### UC-CS-11 — Track tabs for every module (testid derivation)
- **Preconditions / state:** Each module opened in turn.
- **Input:** Open each card, enumerate tabs.
- **Action flow:** 1. Open each of the 4 cards. 2. Read the `cold-track-*` testids.
- **Expected output (module → tab testids, derived by `k.toLowerCase().replace(/[^a-z0-9]+/g,"-").replace(/(^-|-$)/g,"")`):**
  - search: `cold-track-literature`, `cold-track-databases`, `cold-track-patents`, `cold-track-internal`
  - analysis: `cold-track-ad-hoc-compute`, `cold-track-validated-workflows`
  - design: `cold-track-generate`, `cold-track-predict-activity`, `cold-track-optimise-properties`, `cold-track-rank-candidates`
  - models: `cold-track-train`, `cold-track-adapt`, `cold-track-optimise`
- **Information flow:** `m.tracks` → testid slug.
- **Pass criteria:** All 13 tab testids present across the 4 cards; labels match `tr.k`.
- **Edge / error cases:** "Ad-hoc compute" → hyphenated slug `ad-hoc-compute` (apostrophe-free). Models "Optimise" and Design "Optimise properties" produce distinct slugs.

### UC-CS-12 — Example rows seed the composer (never send)
- **Preconditions / state:** Design & generate open, Generate tab active.
- **Input:** Click "Generate candidates for this target with drug-like properties."
- **Action flow:** 1. Open `design`. 2. Click that `cold-example` row.
- **Expected output:** Each example is a `cold-example` button rendered as `"…"` (curly-quoted) with a trailing ChevronRight; click fires `onSeed(text)` → composer seeded with the exact example text; no send.
- **Information flow:** `ExampleRow.onClick` → `onSeed`.
- **Pass criteria:** Composer value equals the clicked example (with the quotes stripped — the seed passes the raw `text`, the quotes are display-only). No message posted.
- **Edge / error cases:** Display shows curly quotes but the SEED value is the raw `text` (no quotes) — assert the composer does NOT contain literal `“`/`”`.

### UC-CS-13 — Domain chips appear only on the Validated-workflows track
- **Preconditions / state:** Data analysis open, "Ad-hoc compute" tab active.
- **Input:** Switch to "Validated workflows".
- **Action flow:** 1. Open `analysis`. 2. Confirm no domain chips under Ad-hoc compute. 3. Click `cold-track-validated-workflows`.
- **Expected output:** Under Ad-hoc compute: no `cold-domain-*` chips, three example rows. After switching: six domain chips `cold-domain-dd`, `cold-domain-txn`, `cold-domain-gen`, `cold-domain-str`, `cold-domain-prot`, `cold-domain-clin` (labels Drug discovery / Transcriptomics / Genomics / Structural biology / Proteomics / Clinical), each `aria-pressed="false"`, plus the track's 3 example rows still shown until a chip is picked.
- **Information flow:** `track.domains` truthy only on the Validated-workflows track → renders `COLD_DOMAINS.map` chips.
- **Pass criteria:** Chips present only on the domains-track; 6 chips with correct testids/labels.
- **Edge / error cases:** No other module has a `domains:true` track, so `cold-domain-*` must NOT appear on search/design/models.

### UC-CS-14 — Select a domain chip → shapes replace examples
- **Preconditions / state:** Data analysis → Validated workflows active, no domain selected.
- **Input:** Click `cold-domain-dd` (Drug discovery).
- **Action flow:** 1. Click the Drug-discovery chip.
- **Expected output:** Chip `aria-pressed="true"` (primary border, chip background); the example list is replaced by three `cold-shape` rows for Drug discovery: "Screen a compound set for ADMET liabilities" (needs SMILES or SDF · ~15 min), "Dock a series against a target and rank poses" (needs ligands + target structure · ~1 h), "Explain why a hit series is failing on one property" (needs nothing but the question · seconds). Each shape row shows title + `needs · time` subtitle + ChevronRight.
- **Information flow:** `setDomId(d.id)` → `selectedDomain` = matching `COLD_DOMAINS` entry → `selectedDomain.shapes.map(ShapeRow)`.
- **Pass criteria:** Example rows hidden, 3 shape rows shown with correct titles/needs/time.
- **Edge / error cases:** Selecting the SAME chip again toggles it off (`setDomId(on ? null : d.id)`) → shapes clear, examples return.

### UC-CS-15 — Shape row seeds the composer
- **Preconditions / state:** Drug-discovery domain selected on Data analysis.
- **Input:** Click the "Screen a compound set for ADMET liabilities" shape.
- **Action flow:** 1. Click the `cold-shape` row.
- **Expected output:** `onSeed(shape.seed)` fires → composer seeded with "Screen these SMILES for ADMET liabilities and rank them by developability." (the `seed`, not the title `t`). No send.
- **Information flow:** `ShapeRow.onClick` → `onSeed(shape.seed)`.
- **Pass criteria:** Composer value equals the shape's `seed` (distinct from its display title).
- **Edge / error cases:** The seeded sentence must round-trip through the composer's lane preview to a plausible lane (it's a cloud/ADMET sentence).

### UC-CS-16 — Shapes for every domain (content audit)
- **Preconditions / state:** Data analysis → Validated workflows.
- **Input:** Select each of the 6 domain chips in turn.
- **Action flow:** For each chip, read the 3 shape rows.
- **Expected output:** Exactly 3 shapes per domain (Transcriptomics: differential expression / cell-type composition / batch-corrected integration; Genomics: call variants / compare burden / contamination+relatedness; Structural biology: cryo-EM density map / predict+assess structure / compare model vs map; Proteomics: differential abundance / reconcile with transcriptomic / run-to-run quality; Clinical: stratify+endpoint / check vs SAP / assemble submission section).
- **Information flow:** Static `COLD_DOMAINS[*].shapes`.
- **Pass criteria:** 6×3 = 18 shape rows total across domains; each with `needs` + `time`.
- **Edge / error cases:** Honesty rule: exactly three shapes per domain by design (never the real inventory count) — assert no numeric inventory counts.

### UC-CS-17 — Collapse a card returns it to the grid
- **Preconditions / state:** Any card open.
- **Input:** Click the open card's header.
- **Action flow:** 1. Open a card. 2. Click its `cold-module-expand` again.
- **Expected output:** Card `data-open="false"`, `aria-expanded=false`, chevron ChevronRight, `cold-module-body` removed, `gridColumn:"auto"` (card returns to normal grid cell).
- **Information flow:** `onToggle` sets `openId` back to null.
- **Pass criteria:** Body gone; card collapsed.
- **Edge / error cases:** Local track/domain state discarded on collapse (remounts on next open, back to track 0 / no domain).

### UC-CS-18 — Router self-consistency for card examples (spec §0.5)
- **Preconditions / state:** Dashboard mounted.
- **Input:** For a sample of `COLD_MODULES[*].ex` entries, paste each into `cold-intent-input`.
- **Action flow:** 1. For each example, type it, read `cold-intent-route`.
- **Expected output:** Every example printed on a card produces a non-null verdict (`cold-intent-route` renders; length always >6). Evidence/ad-hoc examples → instant; run/generate/train examples → cloud.
- **Information flow:** `ex` is derived (`withEx`) from `tracks.flatMap(tr=>tr.ex)` so it can't drift from what renders. `readIntent` must return non-null for each.
- **Pass criteria:** No card example returns `null` from `readIntent`.
- **Edge / error cases:** Any example ≤6 chars would fail (none currently are — flag if a future edit shortens one).

### UC-CS-19 — Responsive grid layout
- **Preconditions / state:** Dashboard mounted.
- **Input:** Resize viewport (narrow < 300px per column vs wide).
- **Action flow:** 1. Widen window. 2. Narrow window.
- **Expected output:** Grid uses `repeat(auto-fit, minmax(300px, 1fr))`; wide viewports show up to 2 columns, narrow collapses to 1; an open card always spans full width (`gridColumn:"1 / -1"`).
- **Information flow:** Pure CSS grid on the dashboard container.
- **Pass criteria:** Cards reflow; open card spans full row width.
- **Edge / error cases:** Max container width 720px (`maxWidth:720`, centred).

### UC-CS-20 — Keyboard/ARIA accessibility of cards & tabs
- **Preconditions / state:** Dashboard mounted.
- **Input:** Keyboard navigation.
- **Action flow:** 1. Tab to a card header. 2. Activate with Enter/Space. 3. Tab into the tablist.
- **Expected output:** `cold-module-expand` is a `<button>` with `aria-expanded`; tablist is `role="tablist"` with `aria-label="<module> tracks"`; each tab is `role="tab"` with `aria-selected`; domain chips have `aria-pressed`; intent input has `aria-label="Describe the goal"`; send button `aria-label="Seed the composer with this goal"`.
- **Information flow:** Static ARIA attributes.
- **Pass criteria:** All named ARIA attributes present and reflect state.
- **Edge / error cases:** Icons are `aria-hidden`; example/shape chevrons are decorative (`aria-hidden`).

---

## §2 — Composer (`chat-input.tsx`)

**Root:** `div.chat-input` (bordered pill). Key testids: `chat-input` (textarea), `chat-send-button`, `chat-stop-button`, `chat-input-attached-count`, plus the lane-preview testids (see §3). `MAX_DATASET_REFS = 32`.

### UC-CI-01 — Empty composer: send disabled
- **Preconditions / state:** No text, no attachments, no datasets, not streaming.
- **Input:** None.
- **Action flow:** 1. Observe the send button.
- **Expected output:** `chat-send-button` present but disabled (`!message.trim() && attachedFiles.length===0 && selectedDatasets.length===0`); background muted (`--bm-surface-3`), color `--bm-text-dim`. Placeholder text = the `placeholder` prop (default "What would you like to analyze?").
- **Information flow:** Disabled computed inline from three empty conditions.
- **Pass criteria:** Send disabled with a fully empty composer.
- **Edge / error cases:** Whitespace-only text keeps send disabled (`message.trim()` falsy).

### UC-CI-02 — Typing enables send
- **Preconditions / state:** Empty composer.
- **Input:** Type "run rna-seq on these fastqs".
- **Action flow:** 1. Type into `chat-input`.
- **Expected output:** Send button enabled; background `--bm-text`, color white.
- **Information flow:** `handleInput` → `setMessage(value)`.
- **Pass criteria:** Send enabled once non-space text present.
- **Edge / error cases:** Clearing text back to empty re-disables send.

### UC-CI-03 — Enter sends, Shift+Enter inserts newline
- **Preconditions / state:** Composer has text.
- **Input:** "line1", then Shift+Enter, then "line2".
- **Action flow:** 1. Type "line1". 2. Press Shift+Enter. 3. Type "line2". 4. Press Enter.
- **Expected output:** Shift+Enter adds a newline (no send); Enter (no shift) calls `handleSend` and posts the message; on send the textarea clears and its height resets to `auto`.
- **Information flow:** `handleKeyDown`: `Enter && !shiftKey` → `preventDefault` + `handleSend`.
- **Pass criteria:** Multiline preserved with Shift+Enter; Enter sends and clears.
- **Edge / error cases:** Enter with only whitespace + no attachments → `handleSend` guard `message.trim() || attachedFiles.length || selectedDatasets.length` → no send.

### UC-CI-04 — Textarea auto-grows and caps
- **Preconditions / state:** Composer focused.
- **Input:** Paste ~10 lines of text.
- **Action flow:** 1. Type/paste multiline content.
- **Expected output:** Textarea height grows to `scrollHeight` capped at 200px (`Math.min(target.scrollHeight,200)`); class caps at `max-h-[140px]`. On send, height resets to "auto".
- **Information flow:** `handleInput` sets `style.height` each input.
- **Pass criteria:** Height grows with content and caps; resets after send.
- **Edge / error cases:** Very long single line does not exceed the 200px cap; overflow scrolls.

### UC-CI-05 — Send composes dataset refs invisibly
- **Preconditions / state:** One dataset chip selected + typed text "align these".
- **Input:** Text "align these" + a dataset chip (name "reads.fastq", value "ds-123").
- **Action flow:** 1. Type text. 2. (Dataset added via browser — see UC-CI-10.) 3. Send.
- **Expected output:** `onSend(fullMessage, files?, contextOverride?)` where `fullMessage` = text + newline + `[BioMate dataset: reads.fastq (id: ds-123)]`. After send: text, files, datasets all cleared.
- **Information flow:** `handleSend` joins `message.trim()` with dataset-ref lines → `onSend`. The raw ID is appended to the OUTGOING message text, not shown in the textarea.
- **Pass criteria:** Sent message carries the dataset ref block; textarea never displayed raw IDs.
- **Edge / error cases:** Dataset-only message (empty text) still sends (guard includes `selectedDatasets.length`).

### UC-CI-06 — Lane override forces `intentOverride` on next send
- **Preconditions / state:** Lane preview shown; user clicked an override → `laneOverride` set.
- **Input:** Text "summarise this table"; then click "run a validated pipeline instead" (sets `laneOverride="cloud"`); then Send.
- **Action flow:** 1. Type. 2. Click override in LanePreview. 3. Send.
- **Expected output:** `onSend(..., contextOverride)` with `contextOverride={ intentOverride: "workflow_generation" }` for cloud (or `"research_question"` for instant). After send, `laneOverride` resets to null.
- **Information flow:** `laneOverride` → `contextOverride` mapping in `handleSend`; advisory, never blocks send.
- **Pass criteria:** Correct `intentOverride` passed; resets after one send.
- **Edge / error cases:** No override → `contextOverride` is `undefined`.

### UC-CI-07 — Streaming shows Stop instead of Send
- **Preconditions / state:** `isStreaming=true`.
- **Input:** None.
- **Action flow:** 1. Trigger a streaming reply.
- **Expected output:** `chat-stop-button` rendered (red `--bm-err`, square fill icon), `chat-send-button` NOT rendered; the lane preview is hidden while streaming (`showLanePreview && !isStreaming`).
- **Information flow:** `isStreaming` ternary swaps button; clicking calls `onStop`.
- **Pass criteria:** Stop button visible during streaming; clicking it calls `onStop`.
- **Edge / error cases:** After streaming ends, Send returns.

### UC-CI-08 — Paperclip opens the local file picker
- **Preconditions / state:** Composer idle, `disabled=false`.
- **Input:** Click the paperclip button (title "Attach file").
- **Action flow:** 1. Click paperclip. 2. Choose one or more local files.
- **Expected output:** Hidden `<input type="file" multiple>` triggered (`fileInputRef.current.click()`); on pick, `addFiles` adds `AttachedFile` chips (deduped by name); `onFilesSelected` fired; the input value is reset so the same file can be re-picked.
- **Information flow:** `handleLocalFilePick` → `addFiles` → `setAttachedFiles`.
- **Pass criteria:** Selected files appear as chips; duplicate names ignored.
- **Edge / error cases:** Paperclip `disabled` when `disabled` prop true. Picking zero files is a no-op.

### UC-CI-09 — Attached-file chip: preview & remove
- **Preconditions / state:** At least one attached file chip.
- **Input:** A CSV file "data.csv".
- **Action flow:** 1. Attach "data.csv". 2. Click the Eye (preview) button. 3. Close. 4. Click the X (remove) button.
- **Expected output:** Chip shows FileText icon, truncated name, `(size)` via `formatFileSize`. Eye opens a Dialog titled with the filename + a `getPreviewFileType` Badge ("table" for csv) + size; text files render first 200 lines; csv/tsv render an HTML table (first 50 rows, "Showing 50 of N rows"); binary shows metadata-only card. X removes the chip.
- **Information flow:** `openPreview` reads the File via `FileReader.readAsText` (only for known text exts); `renderPreviewTable` builds the table; `removeFile(id)` filters it out.
- **Pass criteria:** Preview dialog opens with correct type badge + content; remove deletes only that chip.
- **Edge / error cases:** Binary/unknown ext (e.g. `.bam`, `.mrc`) → no text read, metadata-only card ("File attached", name/size/type). `previewLoading` shows "Loading preview…". Read error → loading cleared, empty content.

### UC-CI-10 — Dataset browser button opens the BioMate dataset browser
- **Preconditions / state:** Composer idle.
- **Input:** Click the Database button (title "Browse BioMate datasets").
- **Action flow:** 1. Click the DB button. 2. Select a dataset in `GalaxyDatasetBrowser`.
- **Expected output:** `showDatasetBrowser=true` opens `<GalaxyDatasetBrowser>`; on `onSelect(value, name)` a dataset chip is added (blue-styled, Database icon, deduped by `value`); textarea re-focused.
- **Information flow:** `GalaxyDatasetBrowser.onSelect` → `setSelectedDatasets`.
- **Pass criteria:** Selecting adds a blue dataset chip; duplicate value ignored.
- **Edge / error cases:** DB button `disabled` when `disabled` prop true. Chip X removes it (`setSelectedDatasets` filter).

### UC-CI-11 — Drag-and-drop files onto the composer
- **Preconditions / state:** Composer visible.
- **Input:** Drag a file over the container, then drop.
- **Action flow:** 1. Drag files over the composer. 2. Drop.
- **Expected output:** On dragover with `types.includes('Files')`, `isDraggingOver=true` → an overlay "Drop files to attach" appears (dashed primary border), and the pill border turns primary; on drop, `addFiles(dropped)` attaches them and overlay clears.
- **Information flow:** `handleDragOver`/`handleDragLeave`/`handleDrop`.
- **Pass criteria:** Overlay shows on drag; files attach on drop.
- **Edge / error cases:** Dragging non-file content (no `Files` type) does NOT show the overlay. Leaving the container (`!contains(relatedTarget)`) clears the overlay.

### UC-CI-12 — Dataset-cap indicator tones
- **Preconditions / state:** `sessionDatasetCount` varies.
- **Input:** Set `sessionDatasetCount` to 0, 20, 25, 32.
- **Action flow:** 1. Observe `chat-input-attached-count`.
- **Expected output:** Hidden at 0 (no element). At 20 (<76%): muted `--bm-text-dim`, weight 500, tooltip "20 of 32 attachment references used…". At 25 (≥76%, <100%): amber tone, tooltip "Approaching the 32-attachment cap…". At 32 (≥cap): red `--bm-err`, weight 600, background tint, tooltip "At the 32-attachment cap — older entries will drop… use an S3 folder prefix…". Text renders "N / 32".
- **Information flow:** Inline IIFE computing `pct = count/MAX_DATASET_REFS`, `atCap = count>=32`.
- **Pass criteria:** Correct tone + tooltip per bucket; hidden at 0.
- **Edge / error cases:** Exactly 24 (75%) is still muted; 25 (~78%) crosses to amber (threshold `pct >= 0.76`).

### UC-CI-13 — Lane preview hidden when appropriate
- **Preconditions / state:** Various.
- **Input:** (a) empty text; (b) `showLanePreview=false`; (c) `isStreaming=true`; (d) non-empty debounced text.
- **Action flow:** 1. Toggle each state.
- **Expected output:** Lane preview strip renders ONLY when `showLanePreview && !isStreaming && debouncedMessage.trim()`. Debounce = 350ms (`useDebounce(message, 350)`).
- **Information flow:** Debounced message gates the LanePreview render.
- **Pass criteria:** Strip appears only under the full condition; suppressed otherwise.
- **Edge / error cases:** Typing then quickly clearing (< 350ms) should not flash a stale verdict.

### UC-CI-14 — Programmatic draft prefill (from cold-start / parent)
- **Preconditions / state:** Parent registered `onRegisterSetDraft`.
- **Input:** Parent calls the registered setter with "seeded goal".
- **Action flow:** 1. Cold-start seeds a goal (see §1).
- **Expected output:** `setMessage("seeded goal")` + textarea focused (via `setTimeout(...focus())`).
- **Information flow:** `onRegisterSetDraft(setter)` in a `useEffect`.
- **Pass criteria:** Textarea shows the seeded text and is focused; not sent.
- **Edge / error cases:** Multiple seeds replace (not append) the draft.

### UC-CI-15 — Programmatic file add (from parent)
- **Preconditions / state:** Parent registered `onRegisterAddFiles`.
- **Input:** Parent calls the adder with `File[]`.
- **Action flow:** 1. Parent injects files.
- **Expected output:** `addFiles` runs → chips appear (deduped) + `onFilesSelected` fired.
- **Information flow:** `onRegisterAddFiles(adder)` in a `useEffect`.
- **Pass criteria:** Injected files appear as chips.
- **Edge / error cases:** Duplicate names filtered.

### UC-CI-16 — Multiple attachments + datasets shown together
- **Preconditions / state:** 2 files + 1 dataset selected.
- **Input:** Attach 2 files, add 1 dataset.
- **Action flow:** 1. Attach files. 2. Add dataset.
- **Expected output:** The chip row renders (only when `attachedFiles.length>0 || selectedDatasets.length>0`) with file chips (muted) and the dataset chip (blue). Send composes files array + dataset-ref lines.
- **Information flow:** Two separate maps in the chip row.
- **Pass criteria:** Both chip types visible; all cleared on send.
- **Edge / error cases:** Chip row hidden when both arrays empty.

### UC-CI-17 — Preview a large table (row cap)
- **Preconditions / state:** Attach a CSV with >51 data rows.
- **Input:** A 100-row CSV.
- **Action flow:** 1. Attach. 2. Preview.
- **Expected output:** Table renders header + first 50 rows; footer "Showing 50 of 99 rows" (rows = lines−1). Full text preview capped at 200 lines with "… (truncated at 200 lines)".
- **Information flow:** `renderPreviewTable(lines.slice(1,51))`; content `text.split('\n').slice(0,200)`.
- **Pass criteria:** Row/line caps enforced with the "Showing X of N" note.
- **Edge / error cases:** TSV detected by `.tsv` ext or a tab in the first line → tab delimiter.

### UC-CI-18 — Disabled composer
- **Preconditions / state:** `disabled=true`.
- **Input:** None.
- **Action flow:** 1. Render with `disabled`.
- **Expected output:** Paperclip and Database buttons `disabled`. (Note: the textarea `Textarea` and send button are NOT gated by `disabled` in this component — flagged below.)
- **Information flow:** `disabled` prop on the two attach buttons only.
- **Pass criteria:** Attach buttons disabled when `disabled`.
- **Edge / error cases:** See "Undetermined controls" — textarea/send behaviour under `disabled` is not enforced in-component.

---

## §3 — Lane preview (`lane-preview.tsx`)

**Root:** `data-testid="lane-preview"` with `data-lane`. Sub-testids: `lane-preview-chip`, `lane-preview-read`, `lane-preview-override`, plus the override-active variant `lane-preview-clear-override` (rendered by chat-input when `laneOverride` is set).

### UC-LP-01 — Local heuristic: Instant verdict for an evidence question
- **Preconditions / state:** Composer typing "what is the evidence for X".
- **Input:** "What is the evidence linking this target to disease?"
- **Action flow:** 1. Type; wait past 350ms debounce.
- **Expected output:** `lane-preview` `data-lane="instant"`; `lane-preview-chip` shows green dot + "Instant · cited answer"; sentence "· a cited answer in seconds"; `lane-preview-read` "reads as a question about what is known"; footer "Advisory -- BioMate will confirm before running anything cloud."; override link text "run a validated pipeline instead".
- **Information flow:** `laneForText` INSTANT_RULES match (checked first) → verdict; server arbiter may upgrade later (UC-LP-06).
- **Pass criteria:** Instant verdict + read + advisory footer.
- **Edge / error cases:** Empty text → component renders `null`.

### UC-LP-02 — Local heuristic: Cloud verdict for a named method
- **Preconditions / state:** Composer typing.
- **Input:** "Run DESeq2 on these counts."
- **Action flow:** 1. Type.
- **Expected output:** `data-lane="cloud"`; chip purple dot + "Cloud · validated workflow"; sentence "· a validated workflow (~minutes)"; read "reads as a named method or pipeline"; override link "answer it instantly instead".
- **Information flow:** CLOUD_RULES named-method regex matches.
- **Pass criteria:** Cloud verdict + method read.
- **Edge / error cases:** Instant rules are still checked first — an evidence phrasing wrapping a method name stays Instant.

### UC-LP-03 — Cloud verdict via consequence verb
- **Input:** "Call variants and align these reads."
- **Expected output:** `data-lane="cloud"`; read "reads as a task that produces a validated result".
- **Information flow:** CLOUD_RULES consequence-verb regex.
- **Pass criteria:** Cloud + verb read.
- **Edge / error cases:** —

### UC-LP-04 — Cloud verdict via scale/dataset cue
- **Input:** "Process these 24 samples."
- **Expected output:** `data-lane="cloud"`; read "reads as a task over a set of inputs".
- **Information flow:** CLOUD_RULES scale-cue regex (`\d+\s*samples?` / `these samples`).
- **Pass criteria:** Cloud + scale read.
- **Edge / error cases:** —

### UC-LP-05 — Ad-hoc compute stays Instant
- **Input:** "Summarise this table and plot potency vs logP."
- **Expected output:** `data-lane="instant"`; read "reads as a calculation on a file you already have".
- **Information flow:** INSTANT_RULES ad-hoc-compute regex (checked after evidence, before cloud).
- **Pass criteria:** Instant + compute read.
- **Edge / error cases:** Default fallback (no rule) → Instant, read "reads as a question I can answer directly".

### UC-LP-06 — Server arbiter upgrades the local verdict
- **Preconditions / state:** Text stable for >350ms; `/api/route/classify` reachable.
- **Input:** Any text that the server classifies differently from / same as local.
- **Action flow:** 1. Type stable text. 2. Wait for the debounced fetch.
- **Expected output:** `useServerLane` POSTs `/api/route/classify` `{text}`; on `{lane, why}` valid response, verdict swaps to the server's lane/label/sentence and `lane-preview-read` uses server `why` (prefixed "reads as", with leading "reads as" stripped and trailing period trimmed to avoid "reads as reads as").
- **Information flow:** local heuristic renders immediately → server verdict (when present) preferred (`server || local`).
- **Pass criteria:** Displayed lane matches server response once it returns; read text de-duplicated.
- **Edge / error cases:** Non-ok / `success===false` / lane not in {instant,cloud} / abort / 2500ms timeout → keep local heuristic (verdict cleared to null on each text change until server confirms). Never blocks send.

### UC-LP-07 — Override affordance flips the lane
- **Preconditions / state:** Cloud verdict shown, `onOverride` provided.
- **Input:** Click "answer it instantly instead".
- **Action flow:** 1. Cloud verdict. 2. Click `lane-preview-override`.
- **Expected output:** `onOverride("instant")` called (Cloud verdict offers instant, Instant offers cloud). In chat-input this sets `laneOverride` and re-renders the forced-lane strip: `lane-preview` `data-lane="instant"` + text "Instant · cited answer" + "· forced for this message" + `lane-preview-clear-override` link "let BioMate decide".
- **Information flow:** `onOverride(isCloud ? "instant" : "cloud")` → chat-input `setLaneOverride`.
- **Pass criteria:** Correct forced lane; forced strip shows the clear link.
- **Edge / error cases:** `onOverride` absent → no override button rendered.

### UC-LP-08 — Clear a forced override
- **Preconditions / state:** `laneOverride` set (forced strip shown).
- **Input:** Click "let BioMate decide".
- **Action flow:** 1. Force a lane. 2. Click `lane-preview-clear-override`.
- **Expected output:** `setLaneOverride(null)` → forced strip replaced by the normal `LanePreview` (heuristic/server verdict returns).
- **Information flow:** chat-input `laneOverride` state.
- **Pass criteria:** Override cleared; advisory verdict returns.
- **Edge / error cases:** After a send, override auto-resets even without clicking clear (UC-CI-06).

### UC-LP-09 — Advisory strip never blocks send
- **Preconditions / state:** Any verdict shown.
- **Input:** Send while a verdict is displayed.
- **Action flow:** 1. Type. 2. Send immediately.
- **Expected output:** Send proceeds regardless of lane; the strip is presentational only.
- **Information flow:** LanePreview has no send-gating logic.
- **Pass criteria:** Send is never disabled by the lane preview.
- **Edge / error cases:** In-flight server classify does not delay send.

---

## §4 — Chat message (`chat-message.tsx`)

**Root:** `div.msg` (`.user` or `.assistant`) with `data-testid="chat-message-<id>"`, `data-role`, anchor id `chat-message-anchor-<id>`. Message type is derived from `message.role` + `message.metadata`.

### UC-CM-01 — User text message with attachment chips
- **Preconditions / state:** `message.role="user"`, content includes `[Attached files: a.fastq, b.fastq]` and/or `[BioMate dataset: reads (id: ds-1)]`.
- **Input:** A user message with metadata blocks in the content.
- **Action flow:** 1. Render the user turn.
- **Expected output:** `.msg.user` with a `.bubble`; the visible text has metadata blocks stripped; attachment names surface as `📎 <name>` chips; who-label "You · <time>".
- **Information flow:** Regexes extract `[Attached files: …]` / `[BioMate dataset: …]` names, then strip all metadata blocks from `visibleText`.
- **Pass criteria:** Raw metadata blocks not shown; chips render per file/dataset name.
- **Edge / error cases:** `[Paper content: …]` and trailing content stripped; empty visible text → only chips shown.

### UC-CM-02 — AI markdown text message
- **Preconditions / state:** Assistant message with markdown content, no workflow metadata.
- **Input:** Markdown with a heading, list, code block, table.
- **Action flow:** 1. Render.
- **Expected output:** Who-label "BioMate" (no WF pill); content via `ReactMarkdown` (remark-gfm + rehype-raw); tables wrapped in an `overflow-x-auto` div; links open in new tab unless `#`-anchors; images hide on error. Action row (Copy / Save-as / Regenerate / feedback) shown because content is non-empty.
- **Information flow:** `message.content` → `addCitationLinks` → ReactMarkdown.
- **Pass criteria:** Markdown renders; action row present.
- **Edge / error cases:** Empty content + `progressStatus` → spinner "…" line, no action row.

### UC-CM-03 — Inline citations become anchor links
- **Preconditions / state:** Assistant content with `[1]`, `[2]` and a `## References` section.
- **Input:** Body with `[1]` + a References list starting `[1] Author…`.
- **Action flow:** 1. Render.
- **Expected output:** Body `[1]` → `[[1]](#ref-1)` clickable; References entries get `<span id="ref-1">` anchors; bare URLs in References become markdown links; clicking `[1]` scrolls to the anchor (same-tab for `#` links).
- **Information flow:** `addCitationLinks` splits at the References heading; linkifies body + refs.
- **Pass criteria:** In-body citations link to their reference anchors.
- **Edge / error cases:** No References section → `[N]` links to `#references`. Already-linked `[N](...)` not double-linked.

### UC-CM-04 — research_response strips duplicate References + renders structured display
- **Preconditions / state:** `metadata.type==="research_response"` with `research_response.citations.length>0`.
- **Input:** A research answer + citations.
- **Action flow:** 1. Render.
- **Expected output:** Trailing markdown References section is stripped from the prose (structured citations render below via `<ResearchResponseDisplay>`).
- **Information flow:** content `.replace(/…references?…$/i,'')` when structured citations exist.
- **Pass criteria:** No duplicate References block above the structured citation display.
- **Edge / error cases:** No citations → References left intact.

### UC-CM-05 — Workflow card (pre-panel) renders NextflowWorkflowViewer
- **Preconditions / state:** `metadata.type==="workflow"` + `metadata.workflow` present, never opened in panel (`everInPanel=false`), not a disambiguation/pipeline/chain type.
- **Input:** A generated workflow message.
- **Action flow:** 1. Render.
- **Expected output:** `workflow-artifact-anchor-<id>` wrapper with `data-invocation-id`; inside it a `<NextflowWorkflowViewer>` with the workflow name/domain/steps and the derived `status` (idle/running/paused/completed/failed). "Run again" / "Restart" / "Confirm & Run" footer states come from the viewer per status.
- **Information flow:** `viewerStatus` mapped from `currentExecutionRun.execution.status` (or `isWorkflowRunning`); `onExecute` bubbles params to `onRunWorkflow`.
- **Pass criteria:** Viewer mounted with correct workflow + status; anchor present.
- **Edge / error cases:** `executionStatus` cancelled/error → viewerStatus "failed". No `currentExecutionRun` → uses `message.metadata.workflowViewerStatus || viewerStatus`.

### UC-CM-06 — wf-chip shown once workflow opened in panel
- **Preconditions / state:** Workflow message; panel opened (`isInPanel=true`) → `everInPanel` sticky true.
- **Input:** Open the workflow in the right panel.
- **Action flow:** 1. Open in panel. 2. Close the panel.
- **Expected output:** Full card replaced by `.wf-chip` (FlaskConical icon, name, `domain · N steps` sub, status chip). Status chip class + label: running→`chip-run`/"Running", completed→`chip-ok`/"Done", failed→`chip-fail`/"Failed", else "In panel" (in panel) / "Open in panel" (closed). When closed + `onOpenInPanel` present → an "Open" button. Below: `wf-chip-background-hint` with a status-appropriate sentence.
- **Information flow:** `wasInPanelRef` makes `everInPanel` sticky; `runStatus` from `currentExecutionRun.execution.status`.
- **Pass criteria:** wf-chip (not the full card) shown after first panel open; chip label/hint match run status.
- **Edge / error cases:** While `isInPanel`, the pre-panel branch renders only an invisible `workflow-artifact-anchor-<id>` (no visible card).

### UC-CM-07 — DisambiguationCard
- **Preconditions / state:** `metadata.workflow.workflow_type==="disambiguation"`, not yet in panel.
- **Input:** A workflow message with `candidates[]`.
- **Action flow:** 1. Render. 2. Click a candidate.
- **Expected output:** `<WorkflowDisambiguationCard>` inside `workflow-artifact-anchor-<id>` with message (default "Which workflow best fits what you need?") + candidate list; selecting a candidate calls `onAdjustViaChat("Use <display_name|name>")`.
- **Information flow:** `wf.candidates` → card; `onSelect` → `onAdjustViaChat`.
- **Pass criteria:** Card renders; selection re-submits via chat.
- **Edge / error cases:** Empty candidates → empty list (card still renders with default message).

### UC-CM-08 — Pipeline card (assembled sequential pipeline)
- **Preconditions / state:** `metadata.workflow.workflow_type==="pipeline"`.
- **Input:** A workflow with `pipeline_steps[]`.
- **Action flow:** 1. Render. 2. Confirm run / approve a step / modify a step.
- **Expected output:** `<PipelineListView>` with normalized steps (id/stepNumber/workflowName/params/status/outputs/uses), approval gate; `onConfirmRun`→`onRunPipeline(wf)`; `onApproveStep`→`onApprovePipelineStep`; `onModifyStep`→`onAdjustViaChat("Modify pipeline step …")`.
- **Information flow:** `wf.pipeline_steps` normalized inline.
- **Pass criteria:** Pipeline steps render; run/approve/modify wired.
- **Edge / error cases:** Missing step ids default to `step-<idx>`; status defaults "pending".

### UC-CM-09 — Chain plan card
- **Preconditions / state:** `metadata.workflow.workflow_type==="chain"`.
- **Input:** A workflow with `chain_steps` + `chain_connections`.
- **Action flow:** 1. Render. 2. Click Run chain.
- **Expected output:** `<WorkflowChainPlan>` with chain name/display/domain/description, steps, connections, required inputs, expected outputs; `onRunChain(wf)` when `onRunChain` provided.
- **Information flow:** `wf.chain_*` → card.
- **Pass criteria:** Chain plan renders; run wired only when handler present.
- **Edge / error cases:** No `onRunChain` → run affordance omitted.

### UC-CM-10 — Progress fold line (compact)
- **Preconditions / state:** `metadata.type==="workflow_progress"` OR `id` starts with `progress-`.
- **Input:** A backend narrator progress event.
- **Action flow:** 1. Render.
- **Expected output:** Compact italic line `div.msg.progress` with `data-message-type="workflow_progress"`, `data-progress-kind=<kind>`; a 🔹 marker + a `.speaker-pill` (`data-speaker` from `deriveSpeaker`: qc/loop/wf/agent/plan/find) + the content + `<WhyAnchor>` + `· <time>`. NOT a full assistant card.
- **Information flow:** `deriveSpeaker(kind)` → `SPEAKER_LABELS`; durable fallback via `progress-` id prefix so reloaded lines stay compact.
- **Pass criteria:** Progress lines are single compact rows with the correct speaker pill.
- **Edge / error cases:** kind `workflow.qc_*`→QC, `workflow.autoloop*`→LOOP, `deepagent.*`→AGENT, `plan.*`→PLAN, `findings.*`→FIND, else WF.

### UC-CM-11 — WhyAnchor on a progress line
- **Preconditions / state:** Progress line with `technical.rationale_id` OR (workflowName + phaseId).
- **Input:** A progress event carrying rationale context.
- **Action flow:** 1. Render. 2. Open the why anchor.
- **Expected output:** `<WhyAnchor>` mounts (testid `why-anchor-<safeTestId>`); it lazily fetches `/api/rationale/<id>` (rid path) or `/api/workflows/<name>/phases/<phaseId>/rationale` and renders rationale_text + citation in a popover; renders NOTHING when context missing or the endpoint returns no `rationale_text`.
- **Information flow:** `rationale_id` preferred, else `workflowName`+`phaseId` (`phase_id`/`phase_name`/`name`).
- **Pass criteria:** Why anchor appears only when a curated rationale exists.
- **Edge / error cases:** Endpoint non-ok / empty → anchor renders null (safe to mount unconditionally).

### UC-CM-12 — Proactive suggestion card (progress subtype)
- **Preconditions / state:** progress message, `kind==="proactive_suggestion"` + `technical.proactive_suggestion`.
- **Input:** A proactive suggestion with `quick_replies[]`.
- **Action flow:** 1. Render. 2. Click a quick reply.
- **Expected output:** `proactive-suggestion-card` — a full AI bubble (avatar "B") with markdown content + quick-reply chips (`proactive-quick-reply-<slug>`); clicking → `onSuggestionClick(reply, message)`.
- **Information flow:** `tech.quick_replies` → chips.
- **Pass criteria:** Bubble + quick replies render; clicking submits the reply.
- **Edge / error cases:** No quick replies → chips omitted.

### UC-CM-13 — Chain suggestion card (progress subtype)
- **Preconditions / state:** progress message, `kind==="chain_suggestion"` + `technical.suggestions[]`.
- **Input:** Suggestions + `trigger_workflow`.
- **Action flow:** 1. Render.
- **Expected output:** `chain-suggestion-card` with header "Suggested next steps after <triggerWf>" and per-suggestion items `chain-suggestion-item-<name>` showing display_name, "(N steps)", description.
- **Information flow:** `tech.suggestions` → items; `trigger_workflow` basename → header.
- **Pass criteria:** Header + suggestion items render.
- **Edge / error cases:** Empty suggestions → falls through to the compact progress line (this branch not taken).

### UC-CM-14 — IntentClarificationCard
- **Preconditions / state:** `metadata.intentClarification.candidates.length>0`.
- **Input:** Cross-intent ambiguity payload.
- **Action flow:** 1. Render. 2. Pick / skip.
- **Expected output:** `<IntentClarificationCard>` with candidates + reason; onPick dispatches `biomate:intent-clarification-resolved` CustomEvent; onSkip dispatches `biomate:intent-clarification-skipped`.
- **Information flow:** `_detectCrossIntentAmbiguity` backend → metadata → card → window CustomEvent.
- **Pass criteria:** Card renders; pick/skip dispatch the right events.
- **Edge / error cases:** No candidates → not rendered.

### UC-CM-15 — ParamClarificationCard
- **Preconditions / state:** `metadata.paramClarifications.length>0`.
- **Input:** Missing-required / enum-violation clarifications.
- **Action flow:** 1. Render. 2. Select a value / skip a param.
- **Expected output:** `<ParamClarificationCard>` titled with the workflow name; onSelect dispatches `biomate:param-clarification-resolved` (paramName, value); onSkip dispatches `biomate:param-clarification-skipped`.
- **Information flow:** schema-grounded extraction → metadata → card → CustomEvent → workflow panel patches param.
- **Pass criteria:** Card renders; select/skip dispatch events.
- **Edge / error cases:** None present → not rendered.

### UC-CM-16 — "Redo as a validated run" on compute-result answers
- **Preconditions / state:** Assistant, not workflow, not error, `metadata.toolBlocks.length>0` (`isComputeResultMessage`), and `onRedoAsValidatedRun` provided.
- **Input:** A ran-code/tool answer.
- **Action flow:** 1. Render the action row. 2. Click "Redo as a validated run".
- **Expected output:** `button-redo-as-validated-run` (FlaskConical + "Redo as a validated run", title "Re-run this as a validated Cloud workflow with quality gates and an audit-ready report"); click → `onRedoAsValidatedRun(message)`.
- **Information flow:** parent looks up the user turn and re-sends with `intentOverride='workflow_generation'`.
- **Pass criteria:** Button shown only on compute-result answers; click invokes the handler.
- **Edge / error cases:** Workflow messages, error messages, or answers without toolBlocks → button NOT shown.

### UC-CM-17 — Agent tool blocks (code execution) render above text
- **Preconditions / state:** `metadata.toolBlocks[]` present.
- **Input:** A message that ran code.
- **Action flow:** 1. Render.
- **Expected output:** One `<CodeExecutionBlock>` per tool block, above the markdown text.
- **Information flow:** `message.metadata.toolBlocks` → CodeExecutionBlock.
- **Pass criteria:** Tool blocks render before prose.
- **Edge / error cases:** No toolBlocks → none rendered.

### UC-CM-18 — Action row: copy / save-as / regenerate / download / feedback
- **Preconditions / state:** Assistant, non-error, non-empty content.
- **Input:** A completed AI answer.
- **Action flow:** 1. Click Copy. 2. Open Save-as. 3. Click Regenerate. 4. (If invocation) Download.
- **Expected output:** `button-copy-response-icon` copies `message.content` (toast "Copied response"); `button-save-response` dropdown offers Save as .txt/.md/.docx; `button-regenerate-message-icon` → `onRegenerate`; `button-download-outputs-icon` (only when `effectiveInvocationId`) opens `/api/invocations/<id>/download-all` + `DownloadOutcomePrompt`; `<InlineFeedbackWidget>` when workflow/invocation/galaxy metadata present.
- **Information flow:** `effectiveInvocationId` from run anchor / message / latest run.
- **Pass criteria:** Each action fires its handler; download opens the invocation URL.
- **Edge / error cases:** Clipboard failure → toast "Copy failed". No invocation → download button absent; clicking download without invocation toasts "No outputs yet".

### UC-CM-19 — Error message actions (no action row)
- **Preconditions / state:** `metadata.type==="error"`.
- **Input:** An error message.
- **Action flow:** 1. Render. 2. Click "Try again" / report.
- **Expected output:** The normal action row is NOT shown; instead a bordered row with `button-async-try-again` ("Try again" → `onSuggestionClick("Try again", message)`) and a `<ReportConfusionButton>` carrying errorType/errorMessage.
- **Information flow:** error branch.
- **Pass criteria:** Try-again + report shown; standard action row hidden.
- **Edge / error cases:** Error messages also skip the copy/save/regenerate row (guarded by `metadata.type !== "error"`).

### UC-CM-20 — IND report handoff chip (ADMET/PBPK complete)
- **Preconditions / state:** Workflow name includes admet/pbpk terms + `currentExecutionRun.execution.status==="completed"`.
- **Input:** A completed ADMET or PBPK run.
- **Action flow:** 1. Render.
- **Expected output:** `ind-report-handoff-chip` link to `/ind-report?from_invocation=<invId>`; label "ADMET screening complete" or "PBPK qualification complete" + "Generate IND §2.6 report from these results →". Also `<RollIntoIndAffordance>` shown when a workflow completed (self-hides if no IND project).
- **Information flow:** wfName substring test + completed status.
- **Pass criteria:** Chip appears only for completed ADMET/PBPK; links to the IND report route.
- **Edge / error cases:** Not ADMET/PBPK or not completed → chip absent.

### UC-CM-21 — Speaker pill on non-progress assistant cards
- **Preconditions / state:** Assistant message with `metadata.kind`.
- **Input:** kinds `workflow.qc_*`, `workflow.autoloop*`, `findings.*`, `deepagent.*`, `plan.*`, plain workflow.
- **Action flow:** 1. Render.
- **Expected output:** Who-label "BioMate" + a `.speaker-pill` for qc/loop/find/agent/plan; NO pill for a plain `workflow.*` kind (a workflow card already declares itself).
- **Information flow:** who-label IIFE derives `sp` from `metadata.kind`.
- **Pass criteria:** Meaningful pill shown; `wf` kind produces no duplicate pill.
- **Edge / error cases:** No `metadata.kind` → no pill.

---

## Controls whose behavior could NOT be fully determined from the code (flagged, not guessed)

1. **`chat-input.tsx` — textarea & send under `disabled` prop.** The `disabled` prop only wires to the paperclip and dataset-browser buttons. The `<Textarea>` and `chat-send-button` are NOT gated by `disabled`, so it's unclear (from this component alone) whether a "disabled" composer should still accept typing/sending. Confirm against the parent (`chat-interface.tsx`) whether `disabled` is expected to freeze the whole composer.
2. **`pendingCount` prop (chat-input).** Declared and documented ("messages queued behind the current AI response") but not rendered anywhere in the component body. No visible indicator — cannot test its UI effect here; verify whether a queue badge is expected.
3. **`placeholder` default vs cold-start context.** The composer's default placeholder is "What would you like to analyze?"; the intent-bar has its own placeholder. Whether the parent overrides `placeholder` when seeding from cold-start is not visible in these files.
4. **LanePreview server `why`/`read` exact copy.** The displayed read text depends on the backend `route_classify` `why` string (from `ai_assistant.py`), which is not in these frontend files — only the client de-dup transform ("reads as …" strip) is verifiable here. The server-provided read text itself must be asserted against the live endpoint.
5. **`GalaxyDatasetBrowser` internal UX** (search, list, pagination, Galaxy-vs-S3 sources) — a separate component (`galaxy-dataset-browser.tsx`) not in scope of this read; only its `onSelect(value, name)` contract is exercised here.
6. **`NextflowWorkflowViewer` internal states** (param strip, QC gate, phase cards, footer buttons) — chat-message only wires props/status into it. Its per-state rendering is covered by the existing workflow-panel plan, not re-derived here.
7. **Exact anchor-scroll behavior for `[N]` citations** — links point at `#ref-N`, but the smooth-scroll/focus behavior is browser/route-dependent and not encoded in this component.
