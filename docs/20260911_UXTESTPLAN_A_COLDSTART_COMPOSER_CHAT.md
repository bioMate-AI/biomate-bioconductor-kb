# UX Test Plan — Cluster A · Entry & Conversation (Upgrade + V2)

*2026-09-11. The UX-focused companion to the functional plan
`docs/20260909_TESTPLAN_COLDSTART_COMPOSER_CHAT.md`. Where the functional plan
asks "does the function work?", this plan asks the master-rubric question: "**is
the user's journey through it smooth, honest, and visually correct?**" It scores
every module + function on all **7 rubric dimensions** for **both** the
**Upgrade** and **V2** versions, per the shape mandated by
`docs/20260911_UXTESTPLAN_MASTER_INDEX.md`.*

**Cluster A scope** (master index): Cold-start dashboard (module cards, modality
chips, examples, intent router), Composer + lane preview ("why this?"), Chat
(messages, ClarifyCard, workflow cards, disambiguation, alerts), Sidebar (nav,
collapse, history dots). **V2 spec §§ 00, 06.**

**Source components read for this plan (grounded, not guessed):**
`cold-start-dashboard.tsx`, `lane-preview.tsx`, `chat-message.tsx`,
`clarify-card.tsx`, `clarify-adapter.ts`, `chat-with-artifacts.tsx`,
`app-sidebar.tsx`. Testids and copy strings below are taken verbatim from those
files.

---

## 0. How to run this plan (rubric rules, inherited from the master index)

- **No mocked APIs in any live/E2E step.** Run against `dev-public.biomate.ai`,
  fixture `lifeifei163361@163.com` (password from `E2E_FIXTURE_PASSWORD`), bypass
  header `x-e2e-test-token: biomate-e2e-bypass-token-dev-only`. The lane preview's
  `/api/route/classify` and the sidebar's `/api/workflows/runs*` are **real**
  calls — do not intercept them.
- **A skip is a fail.** If a case can't be run (blocked infra, missing data),
  record *why* and mark it **untested**, never "passed".
- **Audit, don't assert-render.** Screenshot every state; diff against the V2
  spec section cited; list every deviation.
- **Score all 7 dimensions per function:** (1) Journey, (2) States &
  transitions, (3) Visual fidelity, (4) Honesty, (5) Interaction & feedback,
  (6) Responsiveness & a11y, (7) Cross-version Δ.
- **Version definitions** (master index): **Upgrade** = the currently deployed
  data-centric UI. **V2** = the `data_centroid_design_v2` spec target. Each
  function is scored in both columns; where V2 changes an Upgrade behavior, a
  **Δ (upgrade→v2)** row states what changed and whether it improves the journey.

### 0.1 IMPORTANT — code has moved ahead of the V2GAP snapshot

The V2GAP audit (`docs/20260909_V2GAP_COLDSTART_COMPOSER_CHAT.md`, dated
2026-09-09) graded three headline items as UNDONE/PARTIAL-not-wired. **Reading the
live components on 2026-09-11 shows all three have since landed.** This plan tests
the *current* code and flags each as a resolved Δ (with the V2GAP row it
supersedes) so an executor is not misled by the older gap doc:

| V2GAP row (2026-09-09) | Graded then | Actual state in code now | Evidence |
|---|---|---|---|
| ClarifyCard wired into chat (§6.4) | PARTIAL — "built, NOT wired" | **WIRED** — both param + intent bridges render `ClarifyCard` | `chat-message.tsx:63,706-728`; `IntentClarifyBridge` at `:117-158` |
| Modality selector on Design cold-start card | UNDONE | **DONE** — `cold-modality-{sm,pep,bio}` chips, `exBy` per-modality examples, retitled card | `cold-start-dashboard.tsx:138-152,270-378,837-865` |
| "why this?" affordance on lane preview (§6.2) | UNDONE | **DONE** — `lane-preview-why` toggle + `lane-preview-why-reason` plain-language copy | `lane-preview.tsx:253-285` |

The still-open V2 gaps that remain honestly deferred (Project-suggested row,
Skills & experts scope popover, dot-only lane label, per-domain `DOM_COPY`,
sidebar/file-list resize+hide, seed→SearchAnswer routing) are marked **Known gap
/ deferred** on each affected case.

---

## 1. Coverage map

| Module | Functions scored (7 dims each, both versions) | UX cases | V2 §§ |
|---|---|---|---|
| **A1 Cold-start dashboard** | Empty/first-run state; module cards (open/close/single-open/tracks); modality chips (sm/pep/bio switch + example switching + seed threading); example intents (ask/seed); shape rows; domain chips; intent router entry + "why this?" copy honesty | A1-01 … A1-14 | 00 §0.4, §0.5, §0.15 |
| **A2 Composer + lane preview** | Lane badge + consequence sentence; "why this?" toggle (plain-language, no mechanism leak); Instant vs Cloud dot; override affordance; server-arbiter upgrade; seed→edit→submit; advisory-never-blocks | A2-01 … A2-09 | 06 §6.1, §6.2, §6.10 |
| **A3 Chat** | AI text (markdown/code); workflow card AFTER text + "In panel"/wf-chip; ClarifyCard enum vs missing_required (no auto-fill on unselected enum; skip vs pick); IntentClarify (skip must NOT re-submit); DisambiguationCard; alert/status surfaces (error row, speaker pills, IND chip) | A3-01 … A3-12 | 06 §6.4, §6.6, §6.8, §6.9 |
| **A4 Sidebar** | New Chat; nav items (Workflows/Connectors/IND/Data/Models/Design&Generate/Recent Tools/Billing/Settings); collapse toggle; chat-history status dots (running/failed/completed/idle) | A4-01 … A4-07 | 00 §0.8 |

**Total: 42 UX cases.** Every case carries a per-module Δ(upgrade→v2) note; the
per-module Δ tables are consolidated in §6.

---

## 2. Module A1 — Cold-start dashboard (`cold-start-dashboard.tsx`)

Root `data-testid="cold-start-dashboard"` (`:934`). Centred column
`maxWidth:720, margin:0 auto` (`:940-941`). Heading **"What are you trying to
do?"** 18px/600 (`:946-948`). Mounts only when `displayMessages.length===0 &&
!isTyping && !isTypingLocal` (per functional plan; wiring in `chat-interface.tsx`).
V2 spec §0.4 caps width at 840px and requires a `collapse`→thin-launcher link and
a project-scope line — see the Δ note in A1-01.

### A1-01 — Cold-start dashboard · empty first-run state
- **Journey:** Open a new chat → land on the dashboard → read "what can I do here?"
  without an empty box or a wall of names.
- **Precondition / data setup:** Log in as the fixture; click **New Chat**
  (`button-new-chat`, `app-sidebar.tsx:229`). Do not type. Real session, zero
  messages, not streaming.
- **Steps:** 1. New Chat. 2. Observe the dashboard region. 3. Screenshot.
- **Expected UX (per rubric):**
  - *states:* single idle state; no spinner, no "loading modules". Grid renders 4
    cards immediately, all `data-open="false"`.
  - *visual:* heading present, 18px/600; centred ≤720px column; 4
    `cold-module-card` cards in a `repeat(auto-fit, minmax(300px,1fr))` grid
    (`:954`); intent bar (`cold-intent-bar`) above the grid.
  - *honesty:* **no digit-count strings** anywhere on the cards (no "2,455
    workflows", no "N tools") — spec §0.15 no-inventory rule. Assert the card
    bodies contain no `/\d{2,}\s*(workflow|tool|model|pipeline)/i`.
  - *interaction:* nothing fires on load; every control is seed-only.
  - *a11y:* heading is a real text node; cards are `<button>`s with
    `aria-expanded` (`:745`); intent input has `aria-label="Describe the goal"`
    (`:525`).
- **Acceptance (UX-pass ⇔):** `cold-start-dashboard` visible; exactly 4
  `cold-module-card` with `data-module-id` ∈ {search, analysis, design, models};
  titles/subtitles match `COLD_MODULES` (`:205-408`): Search & evidence / "A cited
  answer over literature, databases and patents"; Data analysis / "Work on your own
  data — ad-hoc or a validated workflow"; **Design & generate / "Propose
  candidates — molecules, peptides, proteins — then optimise and rank them"**
  (`:273`); Models / "Train, adapt or optimise a model on your data". No inventory
  digits.
- **Upgrade:** As above; 720px column; no collapse-to-thin-launcher link; no
  project-scope context line.
  **V2:** §0.4 wants max **840px**, a `collapse` text link that switches to the
  `.thinlaunch` (composer + 3 `.modpill` + expand) persisted for the session, and
  (inside a project) the line *"In &lt;project&gt; · its files and instructions are
  in context."* (§0.4.4).
  **Δ:** width 720 vs 840 (minor visual); **thin-launcher + collapse link is
  UNDONE**; project-scope line UNDONE. Neutral-to-regression on returning-user
  journey (a returning user re-reads the full dashboard every time).
- **Known gap / deferred:** thin launcher (§0.4.3) and project-scope line
  (§0.4.4) not implemented — mark untested-for-V2, don't fake a pass.

### A1-02 — Module card · expand / collapse / single-open
- **Journey:** Click a card header → it opens full-width with its tracks → click
  another → the first auto-closes.
- **Precondition:** Dashboard mounted, all collapsed.
- **Steps:** 1. Click Search & evidence header (`cold-module-expand` inside
  `data-module-id="search"`). 2. Confirm `data-open="true"`, body appears. 3. Click
  Data analysis header. 4. Confirm search now `data-open="false"`, analysis
  `data-open="true"`. 5. Re-click analysis header → collapses.
- **Expected UX:**
  - *states:* idle→open→open(other)→collapsed; each transition immediate, no
    animation-stuck state.
  - *visual:* open card `gridColumn:"1 / -1"` (spans full row, `:739`);
    `border-strong` on open (`:735`); chevron flips ChevronRight→ChevronDown
    (`:788`). Exactly one `cold-module-body` in the DOM at any time.
  - *honesty:* n/a.
  - *interaction:* header is one large click target; `aria-expanded` tracks state.
  - *a11y:* `role="tablist"` with `aria-label="<module> tracks"` (`:803`).
- **Acceptance:** single-open enforced (`openId` string, `:931,964`); only clicked
  card open; body mounts/unmounts; chevron + `aria-expanded` reflect state.
- **Upgrade = V2** behaviorally (spec §0.4.2 "only one open at a time"). **Δ:**
  none functional; V2 adds `border-strong` styling which is already present.

### A1-03 — Track tabs render + switch (all 4 modules)
- **Journey:** Open a card → see its tracks as tabs → switch a track → examples
  swap.
- **Precondition:** Each module opened in turn.
- **Steps:** For each of the 4 cards: open it, enumerate `cold-track-*` testids,
  click each non-default track, confirm example rows change.
- **Expected UX:**
  - *states:* first track selected on open (`ti=0`); switching resets any selected
    domain (`setDomId(null)`, `:815`).
  - *visual:* selected tab has primary fill + white text (`:820-822`); pill shape.
  - *interaction:* `role="tab"` + `aria-selected` per tab (`:810-811`).
- **Acceptance:** all 13 tab testids present (derivation `k.toLowerCase().replace
  (/[^a-z0-9]+/g,"-")…`, `:812`):
  - search: `cold-track-literature`, `cold-track-databases`, `cold-track-patents`,
    `cold-track-internal`
  - analysis: `cold-track-ad-hoc-compute`, `cold-track-validated-workflows`
  - design: `cold-track-generate`, `cold-track-predict-filter`,
    `cold-track-optimise-properties-one-pass`, `cold-track-rank-candidates`
  - models: `cold-track-train`, `cold-track-adapt`, `cold-track-optimise`
- **Upgrade:** design tracks are now **"Generate / Predict & filter / Optimise
  properties · one pass / Rank candidates"** (`:278,303,328,353`) — the V2 renames
  are LANDED.
  **V2:** §ColdStart renamed the design tracks; also gives Models a pre-trained
  **"Run a model"** track.
  **Δ:** design-track renames DONE (was UNDONE in V2GAP). Models "Run a model"
  track is **still absent** — Models has only Train/Adapt/Optimise. Mark deferred.
- **Known gap / deferred:** Models "Run a model" pre-trained track (V2GAP row 11)
  not present.

### A1-04 — Modality chips on the Design card (sm / pep / bio)
- **Journey:** Open Design & generate → pick a modality → the example intents
  switch to that modality's phrasing → click one → the seeded goal names the
  modality.
- **Precondition:** Dashboard mounted.
- **Steps:** 1. Open `design`. 2. Confirm a **Modality** chip row renders with
  `cold-modality-sm`, `cold-modality-pep`, `cold-modality-bio` (labels Small
  molecule / Peptide / Protein / biologic, `:141-145,840-863`). 3. `sm` selected by
  default (`aria-pressed="true"`). 4. Read the Generate track examples. 5. Click
  `cold-modality-pep`; confirm examples swap to the peptide set ("Design cyclic
  peptides against this binding site." etc., `:290-293`). 6. Click a peptide
  example → composer seeded. 7. Click `cold-modality-bio`; confirm nanobody/CDR
  examples (`:295-299`).
- **Expected UX:**
  - *states:* modality is local card state, resets to `sm` on re-open (`:718`).
  - *visual:* selected chip has primary border + chip-bg (`:852-853`); label
    "Modality" prefix (`:839`).
  - *honesty:* examples are editorial (3 per track per modality), never a count.
  - *interaction:* `aria-pressed` toggles; switching `pep`↔`bio` re-renders the
    example list live (`trackExamples = track.exBy[mod]`, `:725`).
- **Acceptance:** 3 modality chips present only on the design card (no
  `cold-modality-*` on search/analysis/models — `modalities:true` only on design,
  `:275`); example rows reflect `exBy[mod]`; seeding threads modality via
  `seedWithModality` (`:690-702`) — a peptide/bio seed that doesn't already name
  the modality gets " (&lt;word&gt; design)" appended; `sm` is a no-op.
- **Upgrade:** LANDED as described.
  **V2:** §ColdStart modality selector + seed carries modality (`onSeed(x, mod)`).
  Deployed uses a single-arg `onSeed` and instead **encodes the modality in the
  seed text** (`seedWithModality`) so the downstream router reads it — documented
  design deviation (`:682-702`).
  **Δ:** modality selector DONE (was UNDONE in V2GAP); seed-carries-modality
  achieved via text-encoding rather than a 2nd arg. UX improvement; the only
  visible risk is a double-qualified seed if the escape regex misses a synonym —
  audit the seed text for a stray "(peptide design)" on an already-peptide
  sentence.

### A1-05 — Example intent row seeds the composer (never sends)
- **Journey:** Click a quoted example → composer fills with the raw sentence,
  focused, unsent.
- **Precondition:** Any card open (use Search → Literature).
- **Steps:** 1. Open `search`. 2. Click a `cold-example` row (`:623`). 3. Inspect
  the composer textarea.
- **Expected UX:**
  - *states:* no send; the transcript stays empty (dashboard remains mounted).
  - *visual:* row shows the sentence in **curly quotes** with a trailing
    ChevronRight (`:639-641`); the SEED value is the RAW text (no quotes).
  - *honesty:* nothing runs; matches spec §0.4.2 "a starting point to edit, not a
    command that fires".
  - *interaction:* one click → `onSeed(text)` → parent fills composer + focuses.
- **Acceptance:** composer value === raw example text (assert it does **not**
  contain literal `“`/`”`); no user bubble posted; textarea focused.
- **Upgrade = V2** on seed-not-send. **Δ:** V2 §0.4.2 adds a per-example `ask`/`open`
  action pill (search=`ask`, models=`open`) and card lane/`ok` chips — **UNDONE**
  in deployed `ExampleRow` (plain rows). Mark deferred (V2GAP rows 10). Low impact.
- **Known gap / deferred:** per-example ask/open pills + card lane/ok chips.

### A1-06 — Shape rows (Data analysis → Validated workflows → domain)
- **Journey:** Open Data analysis → Validated workflows track → pick a domain chip
  → examples are replaced by workflow *shapes* (title · what it needs · time) →
  click one → composer seeded with the shape's canonical seed.
- **Precondition:** Dashboard mounted.
- **Steps:** 1. Open `analysis`. 2. Confirm no domain chips under Ad-hoc compute.
  3. Click `cold-track-validated-workflows`. 4. Confirm 6 domain chips
  `cold-domain-{dd,txn,gen,str,prot,clin}` (`:871-895`). 5. Click `cold-domain-dd`.
  6. Confirm the 3 `cold-shape` rows for Drug discovery (`:81-85`). 7. Click the
  ADMET shape → composer seeded with "Screen these SMILES for ADMET liabilities and
  rank them by developability." (the `seed`, not the title). 8. Re-click
  `cold-domain-dd` → shapes clear, examples return (toggle-off, `:879`).
- **Expected UX:**
  - *states:* domain toggle; shapes replace examples while a domain is selected.
  - *visual:* each `cold-shape` shows title (600) + `needs · time` sub (dim) +
    ChevronRight (`:652-679`).
  - *honesty:* **exactly 3 shapes per domain by design** — never the real
    inventory count (spec §0.15). Assert 6×3=18 total across domains; assert no
    numeric inventory count.
  - *interaction:* chips `aria-pressed`; shape click seeds `shape.seed` (distinct
    from title).
- **Acceptance:** chips present only on the domains-track (no `cold-domain-*` on
  search/design/models); 18 shapes total; composer value === `shape.seed`.
- **Upgrade = V2** (spec §0.4.2 `.schip` / `.shaperow`). **Δ:** none.

### A1-07 — Intent router · idle below 7 chars (silence beats "no results")
- **Journey:** Type a stub → no route strip flashes.
- **Steps:** 1. Focus `cold-intent-input`. 2. Type "herg" (4 chars). 3. Confirm
  `cold-intent-route` is NOT rendered; `cold-intent-send` is *enabled* once any
  non-space char present (`canSend`, `:502`).
- **Expected UX:** *honesty:* `readIntent` returns null for `t.length<=6` (`:477`)
  → **no strip, ever** — spec §0.4.2 "silence beats a no-results state". No fake
  "no match" banner. Placeholder = the full example goal (`:524`), not a noun list.
- **Acceptance:** no `cold-intent-route` for ≤6 chars; whitespace-only ⇒
  `canSend=false` (send opacity 0.4, cursor default, `:550-551`).
- **Upgrade = V2** (spec §0.5 "no match, no box"). **Δ:** none.

### A1-08 — Intent router · Instant/evidence goal
- **Steps:** Type "What is the evidence linking this target to disease?"
- **Expected UX:** `cold-intent-route` `data-lane="instant"`; dot is green
  (`--bm-ok`, `:587`); `cold-intent-route-lane` reads "Instant · cited answer";
  `cold-intent-route-domain` chip "Literature" (`DOMAIN_RULES` evidence rule,
  `:433`). *honesty:* the router **restates the goal in system terms** (lane +
  domain), never a ranked list of workflow names or a count (spec §0.5).
- **Acceptance:** lane=instant, label "Instant · cited answer", domain "Literature".
- **Upgrade = V2.** **Δ:** none (router copy is spec-compliant; no count, no name
  list).

### A1-09 — Intent router · Cloud/ADMET goal + domain-owns-lane
- **Steps:** Type "Screen these SMILES for ADMET liabilities and rank them."
- **Expected UX:** `data-lane="cloud"`; dot primary/purple (`:585-586`); domain
  chip "Drug discovery" (ADMET rule at `:449`, ordered **before** the ranking rule
  at `:450` so "rank" doesn't steal the domain). *honesty:* domain read is the
  source of truth for the lane (`:483`) so chip and dot never disagree.
- **Acceptance:** lane=cloud, domain "Drug discovery"; dot matches lane.
- **Upgrade = V2.** **Δ:** none. (For the full 21-row domain→lane matrix reuse
  functional UC-CS-05; this plan only re-verifies the UX invariant "chip and dot
  agree, no inventory".)

### A1-10 — Intent router · seed via send button and via Enter
- **Steps:** Type "Call variants on these samples. Human GRCh38." → (a) click
  `cold-intent-send`; (b) repeat, press Enter in `cold-intent-input`.
- **Expected UX:** both paths call `onSeed(q.trim())` (`:522,540`) → composer
  seeded + focused, **not sent** (no user bubble). *honesty:* spec §0.5 "*Start*
  seeds … it never launches a run."
- **Acceptance:** composer value === goal; no message posted; textarea focused.
  Enter with empty/whitespace ⇒ no-op (`:522` guards `q.trim()`).
- **Upgrade = V2.** **Δ:** none. (Note: deployed labels the CTA as a send-arrow
  glyph, not a "Start" button; V2 §0.4.1 wireframe shows a `[ Start ]` label —
  minor copy Δ, still seed-only.)

### A1-11 — Router self-consistency (spec §0.5 self-test)
- **Journey:** Every example printed on a card must route to a non-null verdict.
- **Steps:** For a sample of `COLD_MODULES[*].ex` (derived via `withEx`,
  `:195-203`, so it can't drift from what renders), paste each into
  `cold-intent-input`, confirm `cold-intent-route` renders.
- **Expected UX:** *honesty:* the cards make a promise about what the router
  understands; the promise must hold. Evidence/ad-hoc examples → instant;
  run/generate/train examples → cloud.
- **Acceptance:** no card example returns null from `readIntent` (all >6 chars);
  peptide/bio design examples route to "Peptide design" / "Protein & biologic
  design" (rules at `:444-445` — LANDED).
- **Upgrade = V2.** **Δ:** peptide/protein-biologic domain routes are now present
  (was PARTIAL in V2GAP row); batch-correction/SAP-specific domains still fold into
  Transcriptomics/Clinical rather than their own labels — minor, mark note.

### A1-12 — Responsive grid + open-card full-width
- **Steps:** 1. Widen the window (2 columns). 2. Narrow below 300px/col (1 column).
  3. Open a card at each width.
- **Expected UX:** *responsiveness:* grid reflows via `auto-fit minmax(300px,1fr)`
  (`:954`); an open card always spans the full row (`gridColumn:"1 / -1"`); the
  container caps at 720px centred. No clipped card, no horizontal scroll.
- **Acceptance:** cards reflow; open card full-width at every width.
- **Upgrade:** 720px cap; grid collapses to 1 col under ~300px/col.
  **V2:** §0.4.2 `.modgrid` collapses to one column under **1100px**; 840px column.
  **Δ:** different breakpoint model (auto-fit vs 1100px media query) and 720 vs
  840 width — visually close, not identical. Neutral.

### A1-13 — Keyboard / ARIA of cards, tabs, chips, intent bar
- **Steps:** Tab through the dashboard; activate a card header with Enter/Space;
  Tab into the tablist; Tab to a domain chip; Tab to the intent input + send.
- **Expected UX:** *a11y:* `cold-module-expand` `<button>` with `aria-expanded`;
  tablist `role="tablist"` + per-tab `role="tab"`/`aria-selected`; domain +
  modality chips `aria-pressed`; intent input `aria-label="Describe the goal"`;
  send `aria-label="Seed the composer with this goal"` (`:544`); all icons
  `aria-hidden`.
- **Acceptance:** every named ARIA attribute present and reflects state; focus
  order is header → tabs → (modality) → (domains) → rows.
- **Upgrade = V2.** **Δ:** none.

### A1-14 — Honesty audit: no inventory, no fabricated numbers (spec §0.15)
- **Steps:** With every card opened and every track/domain/modality selected in
  turn, scan all visible text for digit-count strings, "N results", "N workflows",
  a browsable name list, or a fabricated metric.
- **Expected UX:** *honesty:* the ONLY numbers allowed are the shape `time`
  estimates ("~15 min", "seconds") — a time class, not an inventory. No counts of
  workflows/models/tools; no catalog of names.
- **Acceptance:** zero inventory digits; only time-class strings appear as numbers.
- **Upgrade = V2** (spec §0.15 copy rule 1). **Δ:** none — this is a shared
  invariant both versions must hold.

---

## 3. Module A2 — Composer + lane preview (`lane-preview.tsx`)

Root `data-testid="lane-preview"` with `data-lane` (`:204-206`). Sub-testids:
`lane-preview-chip`, `lane-preview-read`, `lane-preview-override`,
`lane-preview-why`, `lane-preview-why-reason`. The composer itself
(`chat-input.tsx`) is covered functionally in the 2026-09-09 plan §2; this UX plan
scores the **lane-preview surface** and the seed→edit→submit journey it sits in.
Composer-only mechanics (attachments, dataset cap, drag-drop) are pointed at the
functional plan §2 to avoid re-implementing coverage (master rule 7).

### A2-01 — Lane preview appears only under the full gate
- **Journey:** Type into the composer → after a debounce, the advisory strip
  appears above the field → clear the field → it disappears.
- **Precondition:** Composer empty, not streaming.
- **Steps:** 1. Type "What is the evidence for X". 2. Wait ~350ms
  (`useDebounce(message,350)` per functional plan). 3. Confirm `lane-preview`
  renders. 4. Clear. 5. Confirm it disappears.
- **Expected UX:** *states:* strip renders only when
  `showLanePreview && !isStreaming && debouncedMessage.trim()`; hidden while
  streaming and while empty. No flicker of a stale verdict when typing-then-clearing
  under 350ms.
- **Acceptance:** strip visible only under the full condition; `laneForText`
  returns null for empty (`:91`) so `LanePreview` renders nothing (`:190`).
- **Upgrade:** strip appears above the field.
  **V2:** §6.2 open-question notes the preview "currently flickers between lanes
  mid-sentence" — a debounce is the intended mitigation.
  **Δ:** deployed already debounces (350ms) — matches the V2 intent. Neutral→improve.

### A2-02 — Instant verdict · chip, dot, sentence, read
- **Steps:** Type "What is the evidence linking this target to disease?"; wait.
- **Expected UX:**
  - *visual:* `lane-preview-chip` shows a **green** dot (`--bm-ok`, `:192`) +
    label "Instant · cited answer"; secondary "· a cited answer in seconds"
    (`:226`); `lane-preview-read` italic "reads as a question about what is known"
    (`:229-231`); footer "Advisory -- BioMate will confirm before running anything
    cloud." (`:287`).
  - *honesty:* footer states nothing runs on send without confirmation; advisory
    only.
- **Acceptance:** `data-lane="instant"`; green dot; label + sentence + read +
  advisory footer all present.
- **Upgrade:** prints the **lane name** ("Instant · cited answer") *and* a dot.
  **V2:** §6.2 "Say the consequence, not the lane" — **drop the lane name**; a dot
  alone carries instant-vs-cloud beside the domain; the sentence does the work.
  **Δ:** **PARTIAL — still prints the lane label.** This is the remaining §6.2 gap
  (V2GAP row 1). Regression vs V2 intent (the taxonomy word "Instant" leaks).
- **Known gap / deferred:** dot-only (drop lane name) not done.

### A2-03 — Cloud verdict · purple dot + method/consequence read
- **Steps:** (a) "Run DESeq2 on these counts." (b) "Call variants and align these
  reads." (c) "Process these 24 samples."
- **Expected UX:** *visual:* `data-lane="cloud"`; **purple** dot
  (`--bm-primary`); label "Cloud · validated workflow"; sentence "· a validated
  workflow (~minutes)"; read varies: (a) "reads as a named method or pipeline",
  (b) "reads as a task that produces a validated result", (c) "reads as a task over
  a set of inputs" (`CLOUD_RULES` reads, `:61-65`).
- **Acceptance:** cloud lane + purple dot + correct read per rule.
- **Upgrade = V2** on lane detection. **Δ:** same lane-name-leak as A2-02 applies.

### A2-04 — "why this?" toggle · plain-language, no mechanism leak (§6.2)
- **Journey:** See a verdict → click "why this?" → read one plain sentence
  explaining the routing in the user's terms → click again to collapse.
- **Precondition:** Any verdict shown (use the Instant one from A2-02).
- **Steps:** 1. Click `lane-preview-why` (`:253-270`). 2. Read
  `lane-preview-why-reason` (`:272-285`). 3. Click again → collapses.
- **Expected UX:**
  - *states:* `aria-expanded` on the toggle (`:256`); reason paragraph mounts/
    unmounts on toggle (`whyOpen`).
  - *visual:* underlined primary link labelled **"why this?"** (`:269`); reason
    paragraph ≤62ch, dim, 11.5px.
  - *honesty (critical):* the reason copy (`WHY_COPY`, `:76-81`) names the
    **consequence in words** — "This reads like a question I can answer directly …
    so I answer it here, with sources, rather than running a pipeline." It must
    contain **no regex, no keyword list, no confidence percentage, no rule name**
    (spec §6.2 + §6.10 rule 3). Assert the reason text matches neither
    `/\d+(\.\d+)?%/` nor `/regex|rule|keyword|confidence|token/i`.
    Instant vs Cloud show different copy (`WHY_COPY[v.lane]`).
  - *interaction:* keyboard-activatable button.
- **Acceptance:** `lane-preview-why` present; label exactly "why this?" (NOT "why
  this lane?"); toggling shows/hides `lane-preview-why-reason`; reason is
  mechanism-free plain language, lane-specific.
- **Upgrade:** **LANDED** ("why this?" + plain-language reason). This resolves
  V2GAP row 2 (was UNDONE).
  **V2:** §6.2 "why this lane?" → **"why this?"**, one sentence in the user's
  terms, no mechanism.
  **Δ:** DONE and spec-compliant — UX improvement over the V2GAP snapshot.

### A2-05 — Override affordance flips the lane
- **Precondition:** A Cloud verdict shown; composer provides `onOverride`.
- **Steps:** 1. Get a Cloud verdict. 2. Click `lane-preview-override` — label
  "answer it instantly instead" (`:248`). 3. (Instant verdict offers "run a
  validated pipeline instead".)
- **Expected UX:** *interaction:* `onOverride(isCloud ? "instant" : "cloud")`
  (`:236`) → composer forces the lane on the next send (see functional plan
  UC-CI-06 / UC-LP-07/08 for the forced-strip + clear-override round-trip).
  *honesty:* spec §6.10 rule 2 "offer the other lane every time"; the router is a
  default, not a verdict.
- **Acceptance:** override link present and flips to the opposite lane; when
  `onOverride` is absent the link is not rendered (`:232`).
- **Upgrade = V2.** **Δ:** none (override is spec-compliant).

### A2-06 — Server arbiter upgrades the local heuristic (real `/api/route/classify`)
- **Precondition:** Text stable >350ms; dev reachable. **Do NOT mock the endpoint.**
- **Steps:** 1. Type a stable sentence. 2. Wait for the debounced POST
  `/api/route/classify` (`:146`). 3. Observe the verdict swap to the server's
  lane/read.
- **Expected UX:** *states:* local heuristic renders immediately; the server
  verdict (when it returns valid `{lane, why}`) is *preferred* (`v = server||local`,
  `:189`); the read uses server `why` with a leading "reads as" stripped and a
  trailing period trimmed (`:197-200`) so it never doubles to "reads as reads as".
  *honesty:* on non-ok / `success===false` / lane∉{instant,cloud} / abort / 2500ms
  timeout, it **keeps the local heuristic** (`:152-163`) — never a stuck/blank
  strip. Never blocks send.
- **Acceptance:** displayed lane matches the live server response once it returns;
  read de-duplicated; a slow/failed classify leaves a usable local verdict.
- **Upgrade:** server-driven with local fallback.
  **V2:** §ChatView uses a client `LANE_COPY`/`DOM_COPY` table keyed by router lane
  so the preview can't disagree with the router.
  **Δ:** deployed is functionally stronger (real arbiter) but has **no per-domain
  `DOM_COPY` sentence** — it only carries Instant/Cloud, not a domain sentence in
  the composer strip. PARTIAL (V2GAP row: lane-preview single source). Medium.
- **Known gap / deferred:** per-domain `DOM_COPY` sentences in the composer strip.

### A2-07 — Seed → edit → submit journey (cold-start → composer → send)
- **Journey:** Seed from a cold-start example → the composer holds the sentence →
  edit it → the lane preview updates → send.
- **Precondition:** Dashboard mounted.
- **Steps:** 1. Click a `cold-shape` ADMET seed (A1-06). 2. Confirm composer holds
  the seed, focused, unsent. 3. Edit a word. 4. Confirm the lane preview re-reads
  after 350ms. 5. Send.
- **Expected UX:** *journey:* the seed is a **starting point to edit**, not a
  command — the preview re-evaluates on edit; send is one deliberate action.
  *honesty:* nothing ran until send; a Cloud request then goes to the workflow
  panel's settings for a **second** confirmation (spec §6.2 reversibility rule) —
  the expensive lane costs two deliberate actions.
- **Acceptance:** seed lands unsent; preview updates on edit; send posts a user
  turn; Cloud send opens the panel settings (not an immediate run).
- **Upgrade:** LANDED (seed-not-send).
  **V2:** §6.6 adds an explicit **"Ready to send" card** for the seeded-not-sent
  state ("…nothing has run yet", "clear and see suggestions" escape).
  **Δ:** deployed seeds directly into the textarea with **no "Ready to send"
  wrapper card**. PARTIAL — the honest "nothing has run yet" affordance is weaker.
  Medium.
- **Known gap / deferred:** "Ready to send" seeded-state card (§6.6).

### A2-08 — Advisory strip never blocks send
- **Steps:** Type a Cloud-reading sentence; send immediately (before the server
  classify returns).
- **Expected UX:** *interaction:* send proceeds regardless of lane or in-flight
  classify; the strip is presentational (`LanePreview` has no send gating).
- **Acceptance:** send is never disabled by the lane preview; an in-flight classify
  does not delay it.
- **Upgrade = V2** (spec §6.2 "a statement, never a commitment"). **Δ:** none.

### A2-09 — Composer chrome vs V2 anatomy (Experts / instructions / project row)
- **Journey (V2 target):** The composer footer shows `@ data`, **Experts · N on**,
  **Lane: auto**, and an **instructions chip**; a **Project suggested** row can
  appear above the composer.
- **Steps:** 1. Inspect the composer footer. 2. Attach a file / type a
  project-relevant goal. 3. Look for a project-suggested row.
- **Expected UX (V2 §6.1/§6.5/§6.6):** an Experts popover ("Skills & experts · N
  on", *On in &lt;project&gt;*, project-badged, per-question *changed*), an
  instructions chip, and a "This reads like &lt;project&gt; · File it there / Keep
  unfiled" row.
- **Acceptance (Upgrade):** the deployed composer has the attach + dataset-browser
  + lane preview + send, but **no Experts popover, no instructions chip, no
  project-suggested row** (functional plan §2 + V2GAP rows 3/6/8).
- **Upgrade:** none of the Experts/instructions/project-suggested chrome present.
  **V2:** all three required.
  **Δ:** **UNDONE** (three V2 headline items). These are the biggest remaining
  Cluster-A composer gaps. Mark untested-for-V2 (do not fabricate a pass); test
  only the honest absence.
- **Known gap / deferred:** Skills & experts scope popover (§0.9.2/§6.5),
  instructions chip (§6.1), Project-suggested row + filing (§6.6/§6.6.1).

---

## 4. Module A3 — Chat (`chat-message.tsx` + `clarify-card.tsx` + `clarify-adapter.ts`)

Root `div.msg` with `data-testid="chat-message-<id>"`, `data-role`, anchor
`chat-message-anchor-<id>`. Clarify wiring at `:63-68,706-728`; `IntentClarifyBridge`
at `:117-158`.

### A3-01 — AI text message (markdown, code, citations)
- **Journey:** Ask an Instant question → the answer streams in as readable prose
  with working code blocks and citation links.
- **Precondition:** Send an evidence question on dev; let the Instant answer stream.
- **Steps:** 1. Send "What is the evidence linking BRAF to melanoma? Cite it." 2.
  Read the streamed answer.
- **Expected UX:**
  - *states:* while streaming with empty content + `progressStatus`, a spinner "…"
    line shows and **no action row** (functional plan UC-CM-02); once content
    arrives, the action row (Copy/Save/Regenerate/feedback) appears.
  - *visual:* who-label "BioMate"; markdown via ReactMarkdown (gfm + rehype-raw);
    tables wrapped in `overflow-x-auto`; links open new-tab unless `#` anchors.
  - *honesty:* inline `[1]` citations become `#ref-1` anchor links; a
    `research_response` strips the duplicate trailing References block
    (functional UC-CM-03/04) — no doubled reference list.
- **Acceptance:** markdown renders; code blocks render; `[N]` links resolve to
  their `#ref-N`; action row present on the completed answer.
- **Upgrade = V2** structurally (spec §6.8 "result" kind). **Δ:** V2 §6.8 also
  specifies a "mapping card" (Inputs mapped: slot · data chip · confidence) — the
  deployed chat surfaces resolved data as inline chips, not a formal mapping card.
  Minor; mark note.

### A3-02 — Post-run reply is substantive, not "Done." (§6.9.1)
- **Journey:** After a Cloud run completes, the assistant's chat reply gives a
  1–2 sentence answer with the number/verdict that matters.
- **Precondition:** Run a completing Cloud workflow on dev (e.g. an ADMET screen);
  wait for completion.
- **Steps:** 1. Complete a run. 2. Read the assistant's post-run chat line.
- **Expected UX (V2 §6.9.1):** *honesty:* the reply names the finding ("1,284
  genes move at FDR<0.05 …" / "Nothing cleared the safety floor; closest miss
  BM-4488 at hERG 18 µM"), names any caveat (overridden gate, excluded sample),
  never over-asserts, and **points at the artifact** rather than saying "Done."
- **Acceptance (Upgrade):** the reply is whatever the backend `data.response`
  returns; there is **no client-side reply contract** enforcing substance
  (chat-interface only detects a failure narrative — V2GAP row 4). So a bare "Done."
  from the backend would render as-is.
- **Upgrade:** no reply-contract enforcement.
  **V2:** §6.9.1 reply rule (substantive, caveat, artifact-pointer).
  **Δ:** **UNDONE** — enforcement is backend-dependent, not guaranteed in the UI.
  Test observes the actual reply and records whether it meets the contract; a bare
  status is a **fail** to record honestly, not a UI bug to hide.
- **Known gap / deferred:** post-run reply contract (§6.9.1).

### A3-03 — Mid-run narration cadence (§6.9.2)
- **Precondition:** A multi-phase Cloud run in progress on dev.
- **Steps:** Watch the transcript during the run.
- **Expected UX (V2 §6.9.2):** short italic narrator lines at **start / phase
  boundary / gate**, never one per step; each carries a speaker pill
  (`deriveSpeaker`, `chat-message.tsx:90-101`: qc/loop/wf/agent/plan/find) and a
  `WhyAnchor` when a curated rationale exists. Progress lines render compact
  (`div.msg.progress`, `data-message-type="workflow_progress"`), not full cards,
  and survive reload via the `progress-` id prefix (`:246-249`).
- **Acceptance:** progress lines are single compact rows with the correct speaker
  pill; not one-per-step spam.
- **Upgrade:** surfaces backend narrator lines de-duped as compact italic rows.
  **V2:** §6.9.2 cadence (per-step suppression, phase-boundary framing).
  **Δ:** **PARTIAL** — cadence is backend-driven; the client renders correctly but
  does not itself enforce the per-step suppression. Medium (V2GAP row 5).

### A3-04 — Workflow card appears AFTER the AI text + "In panel" transition
- **Journey:** Ask for a Cloud workflow → AI text summary streams → a workflow card
  renders below it → opening it in the panel collapses the card to a wf-chip
  carrying the run status.
- **Precondition:** Send an ADMET/RNA-seq request on dev; get a workflow card.
- **Steps:** 1. Send "Screen these SMILES for ADMET liabilities." 2. Confirm the AI
  text renders, then the workflow card **below** it (functional UC-CM-05;
  `workflow-artifact-anchor-<id>`, `chat-message.tsx:746-759`). 3. Open it in the
  panel. 4. Confirm the card collapses to `wf-chip` (`:644-694`). 5. Close the
  panel.
- **Expected UX:**
  - *states:* pre-panel → full `NextflowWorkflowViewer`; once opened
    (`everInPanel` sticky, `:252-254`) → `wf-chip` only.
  - *visual:* wf-chip shows FlaskConical icon, workflow name (never "undefined" —
    `name || display_name || 'Workflow'`, `:662`), `domain · N steps` sub, and a
    status chip: running→`chip-run`/"Running", completed→`chip-ok`/"Done",
    failed→`chip-fail`/"Failed", else `In panel` (open) / `Open in panel` (closed)
    (`:646-647`). A status-appropriate `wf-chip-background-hint` (`:687`) sits
    below. An **Open** button appears when closed + `onOpenInPanel` (`:676-683`).
  - *honesty:* the chip status mirrors `currentExecutionRun.execution.status`; a
    failed run says "This run did not complete…", never a fake green.
- **Acceptance:** card after text; name never "undefined"; wf-chip replaces the
  full card after first panel-open; chip label + hint match run status.
- **Upgrade = V2** (spec §6.8 result/step-log handoff). **Δ:** none material.

### A3-05 — ClarifyCard · missing_required (inferred pre-select, one-click confirm)
- **Journey:** A request whose required param can be inferred → a confirm-inference
  card with the inferred option pre-selected and its **bound value** visible → one
  click confirms.
- **Precondition:** Send a Cloud request that leaves a required param inferable
  (backend emits `metadata.paramClarifications` with a `missing_required` entry
  carrying `examples`). On dev, an RNA-seq request without an explicit reference
  build is a reliable trigger.
- **Steps:** 1. Trigger the clarification. 2. Confirm a `clarify-card` renders
  (`:721`, `clarify-card.tsx:221`). 3. Confirm the recommended option
  (`clarify-adapter.ts:66-71`, first example `pick:i===0`) shows a **"recommended"**
  badge (`clarify-card.tsx:268-272`) and the mono bound value `field = val`
  (`:275-277`). 4. Read the step counter `clarify-count` `1/N` (`:228-230`). 5.
  Click `clarify-next` (last step label "Confirm and configure", `:344`).
- **Expected UX:**
  - *states:* multi-question ⇒ counter + `clarify-prev`/`clarify-next`;
    `clarify-prev` disabled on step 1 (`:331-333`).
  - *visual:* AlertTriangle amber header (`:226`); numbered options; own-words
    escape as a final numbered option (`:283-314`); footer "binds to a
    &lt;binds&gt;" (`:319`).
  - *honesty (binding rule §6.4):* every option carries the concrete
    `field = value` in mono — the visible promise the answer is typed, never
    re-parsed. Confirm dispatches `biomate:param-clarification-resolved` with the
    typed value (`:100-105`); the chat-with-artifacts bridge patches
    `inline_parameters[paramName]` on the open workflow (`chat-with-artifacts.tsx:
    461-475`) so the panel pre-fills.
    - *interaction:* picking the recommended option and confirming pre-fills the
    panel field in one click.
- **Acceptance:** card renders; inferred option pre-selected + "recommended"
  badge; bound value visible per option; confirm pre-fills the panel param.
- **Upgrade:** **LANDED** — ClarifyCard is wired (resolves V2GAP row 3/§6.4, which
  graded it "built, NOT wired").
  **V2:** §6.4 confirm-inference card, bound values, inferred pre-select, counter,
  own-words escape, Skip/Prev/Next.
  **Δ:** DONE and spec-compliant — the composer's headline V2 addition is present.
  UX improvement over the V2GAP snapshot.

### A3-06 — ClarifyCard · enum_violation must NOT auto-fill an unselected value (the recent fix)
- **Journey:** A request with an invalid enum value → a card whose options are the
  allowed values, **none pre-selected** → the user must choose deliberately →
  skip/confirm applies **nothing** if untouched.
- **Precondition:** Send a Cloud request with an out-of-schema enum (backend emits
  a `paramClarifications` entry `kind:"enum_violation"` with `allowed[]` + the
  rejected `userValue`).
- **Steps:** 1. Trigger the enum-violation card. 2. Confirm **no** option shows the
  "recommended" badge and none is `data-selected` (adapter sets no `pick` for
  enum_violation, `clarify-adapter.ts:52-62`; the card starts that question at the
  internal `NONE` state, `clarify-card.tsx:128-153`). 3. Read the why line: "You
  said \"&lt;userValue&gt;\", but this workflow only supports the values below."
  (`clarify-adapter.ts:60`). 4. **Without** clicking any option, click
  `clarify-skip` (or `clarify-skip-all`). 5. Confirm **no**
  `biomate:param-clarification-resolved` value is applied to the panel.
- **Expected UX:**
  - *honesty (CRITICAL — the recent fix):* a never-chosen enum value must **not**
    be silently emitted as if picked. The `NONE` sentinel guarantees a question
    with no recommended pick emits nothing on skip/confirm (`emit` filters
    `pk[j]===NONE`, `:189-195`; `skipAll` "applies nothing" for NONE, `:211-217`).
    Assert the panel param is **unchanged** after an untouched skip.
  - *states:* once the user *does* click an option, `data-selected` flips
    (`:252-253`) and confirming emits that typed value.
  - *interaction:* deliberate selection required — no default poisons the panel.
- **Acceptance:** enum_violation renders with zero pre-selected options; untouched
  skip/confirm applies no value; a clicked option applies exactly that value.
- **Upgrade:** LANDED (the `NONE`-sentinel no-auto-fill fix is in the code).
  **V2:** §6.4 binding rule — an answer is a chosen schema value, never a silent
  default.
  **Δ:** DONE — this is the exact "unselected enum must NOT auto-fill" behavior the
  task calls out; it is implemented and testable via `clarify-card.test.tsx` /
  `chat-message.clarify-wiring.test.tsx` (cite those unit tests as the fast
  cross-check; the e2e case above is the live confirmation).

### A3-07 — IntentClarify · skip must NOT re-submit
- **Journey:** A cross-intent ambiguous request → a single-question ClarifyCard
  ("Which should I do?") → picking re-submits with `intentOverride`; **skipping
  does nothing** (no re-submit).
- **Precondition:** Send a request that trips `_detectCrossIntentAmbiguity`
  (backend emits `metadata.intentClarification.candidates[]`). A phrasing that
  reads as both a tool search and a workflow generation is the trigger.
- **Steps:** 1. Trigger the intent card via `IntentClarifyBridge` (`chat-message.
  tsx:706-711`, `:117-158`). 2. **Skip** it (`clarify-skip` / `clarify-skip-all`).
  3. Confirm **no** new user turn / no re-submit. 4. Re-trigger; **pick** a
  candidate; confirm a re-submit with `context.intentOverride` fires.
- **Expected UX:**
  - *honesty (CRITICAL):* skip is a no-op. The bridge sets `skippedRef` in
    `onSkip` and guards `onDone` against it (`:132-154`) because ClarifyCard's skip
    path calls BOTH onSkip and onDone on a single-question card — the guard ensures
    skip only dispatches `biomate:intent-clarification-skipped`, which the
    chat-with-artifacts listener treats as a no-op (`chat-with-artifacts.tsx:
    507-509`). A pick dispatches `biomate:intent-clarification-resolved` →
    `sendChatMessageRef.current(originalMessage, undefined, {intentOverride})`
    (`:496-506`).
  - *states:* the card is a single `1/1` question; the recommended candidate
    (primary lane) is pre-selected (`clarify-adapter.ts:105-112`).
  - *binding:* answering "selects one by id; it never re-classifies the sentence"
    (§6.4) — the value is the intent type, dispatched as a workflow-target answer.
- **Acceptance:** skip → zero re-submits (assert no second user turn / no second
  `/api/…/stream` call); pick → exactly one re-submit with the picked
  `intentOverride`.
- **Upgrade:** **LANDED** (bridge + skip-guard present).
  **V2:** §6.4 disambiguation selects by id, never re-parses; a skip is not an
  answer.
  **Δ:** DONE — the skip-must-not-re-submit invariant is implemented via the
  `skippedRef` guard (cite `chat-message.clarify-wiring.test.tsx`). This is the
  exact behavior the task flags.

### A3-08 — DisambiguationCard (several plausible workflows)
- **Journey:** A request that matches several workflows → a card listing candidates
  → clicking one re-asks via chat by name.
- **Precondition:** Send a broad request; backend returns
  `metadata.workflow.workflow_type==="disambiguation"` with `candidates[]`.
- **Steps:** 1. Trigger. 2. Confirm `WorkflowDisambiguationCard` inside
  `workflow-artifact-anchor-<id>` (`chat-message.tsx:803-817`). 3. Read the default
  prompt "Which workflow best fits what you need?" (`:813`). 4. Click a candidate.
- **Expected UX:** *interaction:* `onSelect` → `onAdjustViaChat("Use
  <display_name|name>")` (`:815`) — re-submits via chat, not a silent pick.
  *honesty:* empty candidates ⇒ card still renders with the default message (no
  crash, no fabricated list).
- **Acceptance:** card renders; selection re-submits by name.
- **Upgrade:** disambiguation is a separate legacy card (not routed through
  ClarifyCard).
  **V2:** §6.4 folds "disambiguate between workflows" into the typed clarification
  (select by id). The intent bridge (A3-07) already does this; the
  `workflow_type==="disambiguation"` path is a **parallel legacy surface** that
  re-classifies by name.
  **Δ:** PARTIAL — two disambiguation surfaces coexist (typed intent bridge vs
  name-based disambiguation card). V2 prefers the typed-by-id path. Note for
  consolidation; not a blocker.

### A3-09 — Alert / status surfaces (error row, speaker pills, IND chip)
- **Journey:** Distinguish an informational chip, a running/qc speaker pill, and a
  hard error with recovery actions.
- **Precondition:** (a) A completed ADMET/PBPK run (IND chip). (b) A qc/loop
  progress line (speaker pill). (c) A backend error message
  (`metadata.type==="error"`).
- **Steps:** 1. Complete an ADMET run → confirm `ind-report-handoff-chip`
  (blue-bordered link, `chat-message.tsx:1042-1043`) reading "ADMET screening
  complete … Generate IND §2.6 report …" linking to `/ind-report?from_invocation=`.
  2. During a run, confirm a qc/loop/find speaker pill on the progress line. 3.
  Force an error → confirm the standard action row is **hidden** and instead a
  bordered row shows `button-async-try-again` ("Try again", `:1160-1169`) + a
  `ReportConfusionButton` carrying errorType/errorMessage.
- **Expected UX:**
  - *honesty (CRITICAL):* a failed/errored message shows a **static** recovery row,
    never a spinner, never "Analysis in progress…" (rubric dim 4 + CLAUDE.md
    findings standard). The IND chip appears **only** for completed ADMET/PBPK
    (substring test + `status==="completed"`), never speculatively.
  - *visual:* the IND chip is the blue info-style banner; the error row is
    border-top separated; speaker pills carry a word (qc/loop/wf/agent/plan/find),
    color never the sole carrier (spec §0.12).
- **Acceptance:** error row replaces the action row on `type==="error"`; IND chip
  only on completed ADMET/PBPK; speaker pill present on qc/loop/etc lines.
- **Upgrade:** the deployed chat has **no generic warn/info/error *banner*
  component** — the CLAUDE.md "alert banners (warn/error/info)" item maps to (i)
  the error-message recovery row, (ii) the blue IND info chip, and (iii) speaker
  pills / status vocab, not a single Alert primitive.
  **V2:** §0.12 status vocabulary (word + colour) is the shared model; §6.7
  cross-lane handoff blockers ("blocked input", "needs a licence") are the nearest
  V2 "alert" surfaces.
  **Δ:** deployed lacks §6.7 handoff/blocker alerts (blocked-input chip, licence
  inline resolve). Mark as a gap; test only what exists (error row + IND chip +
  pills). Do not fabricate a banner test.
- **Known gap / deferred:** §6.7 cross-lane handoff blockers (blocked input,
  credential inline).

### A3-10 — User turn renders attachment chips, strips metadata blocks
- **Steps:** Send a message with an attached file + a dataset ref.
- **Expected UX:** *honesty:* `[Attached files: …]` / `[BioMate dataset: … (id:
  …)]` / `[Paper content: …]` blocks are **stripped** from the visible bubble;
  attachment names surface as `📎 <name>` chips; who-label "You · <time>"
  (functional UC-CM-01). Raw dataset IDs never shown in the bubble.
- **Acceptance:** metadata blocks not visible; chips render per file/dataset.
- **Upgrade = V2** (spec §6.8 "your turn" = sentence + data chips). **Δ:** none.

### A3-11 — Action row (copy / save-as / regenerate / download / feedback)
- **Steps:** On a completed AI answer: Copy; Save-as (.txt/.md/.docx); Regenerate;
  Download (if invocation); observe feedback widget.
- **Expected UX:** *interaction:* `button-copy-response-icon` copies content (toast
  "Copied response"; "Copy failed" on error); `button-save-response` dropdown;
  `button-regenerate-message-icon`; `button-download-outputs-icon` only when an
  invocation exists (else toast "No outputs yet"); `button-redo-as-validated-run`
  only on compute-result answers (`hasToolBlocks`, `chat-message.tsx:232-237,1128`).
  *honesty:* each action gives immediate feedback; disabled/absent states are
  honest (no download button without an invocation).
- **Acceptance:** every present action fires its handler with feedback; download
  opens `/api/invocations/<id>/download-all`; redo-as-validated shown only on
  compute results.
- **Upgrade = V2** (§6.7 "Redo as a validated run" handoff is the compute→cloud
  path). **Δ:** none material.

### A3-12 — Speaker pill on non-progress assistant cards
- **Steps:** Render assistant messages with `metadata.kind` ∈ {workflow.qc_*,
  workflow.autoloop*, findings.*, deepagent.*, plan.*, plain workflow}.
- **Expected UX:** *visual:* who-label "BioMate" + a `.speaker-pill` for
  qc/loop/find/agent/plan; **no pill** for a plain `workflow.*` kind (the workflow
  card already declares itself) — functional UC-CM-21. Color never the only
  carrier (spec §0.12).
- **Acceptance:** meaningful pill shown; `wf` kind produces no duplicate pill; no
  `metadata.kind` ⇒ no pill.
- **Upgrade = V2** (spec §0.12). **Δ:** none.

---

## 5. Module A4 — Sidebar (`app-sidebar.tsx`)

Root: the sidebar column (`:162`). Testids used below are verbatim from the file.
**Note:** the deployed sidebar has evolved well past the CLAUDE.md checklist —
it now carries Connectors, IND Report, Data, Models, Design & Generate nav items,
and no longer has "CRO Library"/"Workflows→StarredWorkflows"/"Runs→/dashboard"
entries. Test the *current* nav.

### A4-01 — New Chat
- **Steps:** Click `button-new-chat` (`:229`).
- **Expected UX:** *journey:* starts a fresh conversation (→ cold-start dashboard,
  A1-01); label "New Chat" + sub "Start a fresh AI conversation" (`:232-233`).
  *interaction:* immediate; no project picker gate (spec §6.6.1 no-precondition
  rule — DONE).
- **Acceptance:** fires `onNewChat`; lands on the empty cold-start; no where-should
  -this-live picker.
- **Upgrade:** DONE (never had a picker).
  **V2:** §6.6.1 nav copy "New chat · Ask, analyse, or start a run" (label = what
  the user can do, not the filing mechanism).
  **Δ:** the sub-label differs ("Start a fresh AI conversation" vs the V2 anchor
  text). Minor copy Δ; the no-precondition rule is satisfied.

### A4-02 — Workspace nav items (each opens its surface)
- **Steps:** Click each: `button-workflows-nav` (→ WorkflowHistoryDialog, runs tab,
  `:236-250`, with a `workflows-running-badge` when `runningCount>0`, `:246`);
  `button-connectors-nav` (→ ConnectorsDialog, `:251-262`); `button-ind-report`
  (→ `/ind-report`, `:263-269`); `button-data-nav` (→ `/files`, `:270-276`);
  `button-models-nav` (→ `/models`, `:277-283`); `button-design-generate-nav`
  (→ `/design`, `:284-290`); `button-recent-tools` (→ RecentToolsDialog,
  `:291-297`); `button-billing-nav` (→ `/billing`, `:298-304`);
  `button-settings-sidebar` + footer `button-settings` (→ SettingsDialog,
  `:431-438,455-465`).
- **Expected UX:**
  - *interaction:* each click either opens a dialog or navigates; the running badge
    reflects a **real** `/api/workflows/runs/overview?...&status=running` poll every
    30s (`:107-118`).
  - *visual:* each item = icon + label + one-line sub; consistent 13px label / 11px
    sub.
  - *honesty:* the running badge shows only when `runningCount>0`; no fabricated
    count.
- **Acceptance:** every nav testid present; each opens the correct dialog/route;
  the running badge appears only with a live running run.
- **Upgrade:** the nav set above.
  **V2:** §0.8 anchor-text rule — a rail item carries a **label only**; the
  explanation belongs **on the surface**, not as a truncated rail subtitle.
  **Δ:** **the deployed sidebar violates §0.8** — every item has a subtitle
  ("Run history, browse & import pipelines", "Databases, LLMs & platform
  integrations", etc.). V2 wants label-only. Note as a copy/IA regression vs V2
  (out-of-scope for the V2GAP composer audit but in-scope here for the sidebar).
  Also: Connectors sub "Databases, LLMs & platform integrations" is exactly the
  §0.8-cited *false/too-long* subtitle the spec warns against.
- **Known gap / deferred:** §0.8 label-only nav + on-surface anchor text.

### A4-03 — Projects section (expand/collapse, project sub-links, shared badge)
- **Steps:** 1. Toggle `button-projects-section` (`:308-317`). 2. Expand a project
  (`button-project-<id>`) → confirm Chats/Files/Workflows sub-links
  (`project-link-*-<id>`, `:336-347`). 3. Confirm a `shared` badge on a project
  whose `userId !== user.id` (`:330-332`). 4. `button-new-project` (`:353-360`).
- **Expected UX:** *states:* projects fetched from `/api/projects` (real, survives
  reload, `:129-133`); refreshes on `biomate:projects-updated`. *honesty:* empty →
  no fake projects. *visual:* active project highlighted.
- **Acceptance:** section toggles; sub-links navigate with the right query params;
  shared badge only on others' projects.
- **Upgrade = V2** roughly (project rail). **Δ:** V2 §0.11 wants the file-list /
  sidebar drag-resizable + collapsible; not tested here (that's the panel plan) —
  see A4-06.

### A4-04 — Chat-history status dots (running / failed / completed / idle)
- **Journey:** Each recent chat carries a colored dot reflecting its latest run's
  status.
- **Precondition:** Have chats with runs in ≥2 states (start one run, let one
  fail/complete) via the real API — do NOT mock `/api/workflows/runs`.
- **Steps:** 1. Observe `history-dot-<chatId>` (`:393`) per chat. 2. Confirm colors:
  running → `--bm-accent` (blue) + pulse animation; failed → `--bm-err` (red);
  completed → `--bm-ok` (green); none → `--bm-border-strong` (grey/idle)
  (`:386-393`). 3. Confirm the dot `title` = the status word ("running"/"failed"/
  "completed"/"idle").
- **Expected UX:**
  - *states:* map built from a real `/api/workflows/runs?limit=50` poll every 15s
    (`:74-101`); precedence running > failed > completed per session (`:88-91`).
  - *honesty:* color is not the only carrier — the `title` word backs it (spec
    §0.12). Idle = grey, not a fake green.
  - *interaction:* running dot pulses (`animation: pulse 1.5s infinite`).
- **Acceptance:** dot color + title match the real run status per chat; running
  pulses; idle is grey.
- **Upgrade:** as above (blue=running/red=failed/green=completed/grey=idle).
  **V2:** §0.12 status vocab word+colour.
  **Δ:** matches §0.12 (each state has a word via `title`). CLAUDE.md's older
  "blue=running, red=failed, green=completed (empty=no run)" is satisfied. Neutral.

### A4-05 — Footer (identity, settings, sign out)
- **Steps:** Confirm the avatar initials, name/email (`:443-454`), footer
  `button-settings` (gear → SettingsDialog), `button-logout` (→ logout + `/login`).
- **Expected UX:** *honesty:* real user name/email from `useAuth`; falls back to
  "Researcher"/"researcher@biomate.ai" only when absent. *interaction:* logout
  awaits then redirects.
- **Acceptance:** identity reflects the fixture; settings opens; logout signs out.
- **Upgrade = V2.** **Δ:** none.

### A4-06 — Collapse toggle (button-sidebar-toggle)
- **Steps:** Click `button-sidebar-toggle` (`:211-223`, title "Collapse sidebar").
- **Expected UX:** *interaction:* fires `onToggleSidebar` (parent hides the sidebar
  and shows an icon-rail / reveal control). *a11y:* the button has a title.
- **Acceptance:** the sidebar hides; a reveal affordance remains (the parent must
  never leave the app with no way back — spec §0.11).
- **Upgrade:** collapse fires the parent handler; the icon-rail / reveal behavior
  lives in the parent (`chat-with-artifacts.tsx` resizes the *workflow panel* only,
  per V2GAP).
  **V2:** §0.11 "every view resizes and hides" — sidebar drag-resizable from a 6px
  grip + collapsible + a labelled reveal control; narrow-viewport gets a *narrower*
  sidebar, never none; collapse is session-only.
  **Δ:** **PARTIAL/UNDONE** — deployed has a collapse toggle but **no drag-resize
  grip, no `Grip`/`Reveal`/`useCollapse` model, no narrow-viewport-narrower rule**
  for the sidebar (V2GAP surface-1/surface-4 rows). Verify a reveal control exists
  after collapse (if none, that's a §0.11 violation — "a collapsed view with no way
  back is indistinguishable from a broken one"). Medium.
- **Known gap / deferred:** §0.11 sidebar drag-resize + reveal control + narrow
  -viewport handling.

### A4-07 — Empty / honest states in the sidebar
- **Steps:** With a fresh account (no chats, no projects, no runs): observe the
  chat-history region and projects section.
- **Expected UX:** *honesty:* chat history shows "No chats yet" (`:423-426`), not a
  fake list; projects section shows only the New-project affordance; no dots
  without runs (idle grey only if a chat exists).
- **Acceptance:** honest-empty copy present; no fabricated entries/counts.
- **Upgrade = V2** (rubric dim 4). **Δ:** none.

---

## 6. Per-module Δ (upgrade → v2) tables

### 6.1 A1 Cold-start
| Function | Upgrade | V2 target | Δ / verdict |
|---|---|---|---|
| Empty state / width | 720px, no thin-launcher, no project line | 840px, `collapse`→thin-launcher, project-scope line (§0.4) | thin-launcher + project line **UNDONE**; width minor. Neutral→slight regression for returning users |
| Module cards | single-open, retitled Design card, renamed design tracks | §0.4.2 | **retitle + track-renames DONE** (were UNDONE in V2GAP). Improvement |
| Modality chips | `cold-modality-{sm,pep,bio}`, per-modality `exBy`, seed-encoded modality | §ColdStart modality selector, `onSeed(x,mod)` | **DONE** (was UNDONE). Improvement; seed encodes modality in text vs 2nd arg |
| Example rows | plain seed rows | + `ask`/`open` pills + card lane/ok chips | pills/chips **UNDONE** (low) |
| Intent router | lane + domain, no count/name-list, chip=dot agree | §0.5 | matches spec. Neutral |
| Models "Run a model" track | absent | pre-trained track | **UNDONE** (medium) |

### 6.2 A2 Composer + lane preview
| Function | Upgrade | V2 target | Δ / verdict |
|---|---|---|---|
| Lane label | prints "Instant/Cloud · …" + dot | **drop lane name**, dot-only (§6.2) | **PARTIAL** — name still leaks (medium regression vs V2) |
| "why this?" | `lane-preview-why` + plain-language, mechanism-free reason | rename + one plain sentence (§6.2) | **DONE** (was UNDONE). Improvement |
| Override | offers the other lane, never blocks | §6.10 | matches. Neutral |
| Server arbiter | real `/api/route/classify`, local fallback | client `LANE_COPY`/`DOM_COPY` | stronger, but **no per-domain sentence** (PARTIAL, medium) |
| Seeded-not-sent | seeds into textarea | "Ready to send" card + "nothing has run yet" (§6.6) | **PARTIAL** — no wrapper card (medium) |
| Experts / instructions / project row | none | Experts popover + instructions chip + project-suggested row (§6.1/6.5/6.6) | **UNDONE** (high — the biggest composer gaps) |

### 6.3 A3 Chat
| Function | Upgrade | V2 target | Δ / verdict |
|---|---|---|---|
| ClarifyCard param (missing_required) | wired, inferred pre-select, bound values, counter, own-words | §6.4 | **DONE** (was "not wired"). Improvement |
| ClarifyCard enum (no auto-fill) | `NONE` sentinel — untouched enum applies nothing | §6.4 binding rule | **DONE** — the exact recent fix. Improvement |
| IntentClarify skip | `skippedRef` guard — skip never re-submits | §6.4 select-by-id, skip≠answer | **DONE**. Improvement |
| Workflow card after text + wf-chip | card→wf-chip on panel-open, status chip, never "undefined" | §6.8 | matches. Neutral |
| Post-run reply contract | backend `data.response` as-is | substantive 1–2 sentence answer (§6.9.1) | **UNDONE** — no client enforcement (high) |
| Mid-run narration cadence | compact de-duped narrator lines | start/phase/gate, per-step suppression (§6.9.2) | **PARTIAL** — backend-driven (medium) |
| Disambiguation | legacy name-based card + typed intent bridge coexist | typed select-by-id (§6.4) | **PARTIAL** — two surfaces; consolidate |
| Alerts | error row + IND chip + speaker pills; no §6.7 blockers | status vocab (§0.12) + handoff blockers (§6.7) | blocker/handoff alerts **UNDONE** (medium) |

### 6.4 A4 Sidebar
| Function | Upgrade | V2 target | Δ / verdict |
|---|---|---|---|
| New Chat | no picker gate | §6.6.1 no-precondition | **DONE**. Neutral |
| Nav items | icon + label + **subtitle** each | **label only**, anchor text on surface (§0.8) | **regression vs V2** — subtitles violate §0.8 (incl. the exact Connectors subtitle §0.8 warns against) |
| History dots | blue/red/green/grey + `title` word | §0.12 word+colour | matches. Neutral |
| Collapse | toggle fires parent; no grip/resize | drag-resize + reveal + narrow-viewport rule (§0.11) | **PARTIAL/UNDONE** (medium); verify a reveal control exists |
| Empty states | "No chats yet", no fake entries | rubric dim 4 | matches. Neutral |

---

## 7. Honesty notes for the executor

- **Trust the code, not the 2026-09-09 V2GAP doc, where they disagree.** Three
  V2GAP "UNDONE/not-wired" items (ClarifyCard wiring, modality chips, "why this?")
  are LANDED in the current tree; §0.1 lists the exact lines. Do not fail those
  cases on the strength of the stale gap doc.
- **Cases A2-02/03 (dot-only), A2-07 (Ready-to-send), A2-09 (Experts/instructions/
  project row), A3-02 (reply contract), A3-09 (§6.7 blockers), A4-02 (label-only
  nav), A4-06 (§0.11 sidebar resize/reveal), A1-01 (thin-launcher/project line),
  A1-03 (Models "Run a model" track), A1-05 (ask/open pills)** are honestly
  DEFERRED per the V2GAP/spec. Test the *honest absence* (assert the element is not
  there); do NOT fabricate a pass, and mark the V2 column **untested** where the
  behavior doesn't exist yet.
- **The two clarify-honesty invariants the task singles out are implemented and
  unit-tested:** unselected-enum-no-auto-fill (`NONE` sentinel, A3-06) and
  intent-skip-no-re-submit (`skippedRef` guard, A3-07). The fast cross-checks are
  `clarify-card.test.tsx`, `clarify-adapter.test.ts`, and
  `chat-message.clarify-wiring.test.tsx`; the e2e cases above are the live
  confirmation. (Per master rule 7: cite the unit tests rather than re-implementing
  their coverage in e2e.)
- **Never mock the live endpoints:** `/api/route/classify` (A2-06),
  `/api/workflows/runs*` (A4-02/04). A skipped case is a fail — record why.
