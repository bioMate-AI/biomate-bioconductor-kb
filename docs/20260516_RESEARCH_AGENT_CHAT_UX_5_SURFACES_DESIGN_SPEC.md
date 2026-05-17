# BioMate Research-Agent UI — Detailed Design Spec for Claude Design

**Date:** 2026-05-16
**Audience:** Claude Design (Anthropic design tool) + human reviewers
**Engineering companion doc:** `docs/20260515_RESEARCH_AGENT_UX_REQUIREMENTS.md`
**Status:** Draft — pending design review

---

## Context and Scope

BioMate is a chat-driven bioinformatics workflow platform. Users describe a
research goal in chat; the system plans + executes Nextflow workflows on
AWS Batch and narrates progress back as italic 🔹 chat lines (current
state, shipping in commit `2bd9570cf`).

The platform already has substantial *unsurfaced* capability for:
1. Task decomposition (breaking one query into multiple parallel sub-tasks)
2. Pilot study mode (cheap sample run before the full pipeline)
3. Experimental comparison (A vs B run with parameter diff + recommendation)

This spec defines five UI surfaces that expose those capabilities through
the existing chat + workflow-panel IA. **No new dashboards, no new tabs.**
Everything renders inline in the conversational flow.

Patterns are adapted from auto-research agents in the CS domain
(Anthropic/OpenAI/Perplexity Deep Research, Sakana AI Scientist,
Devin/Cognition, AutoGen, Weights & Biases) — adapted to BioMate's
high-cost, gate-driven, scientist-audience domain.

---

## Reference: Existing Design Language

- Chat bubbles + italic 🔹 progress lines (current — see
  `nextflow-workflow-viewer.tsx` and `chat-message.tsx`)
- Workflow panel with phase cards, QC settings, run footer
  (current — `nextflow-workflow-viewer.tsx`)
- Reference HTML at `http://localhost:7779/cro/Workflow%20Panel%20Redesign.html`
- Token palette: oklch — `--bm-accent` blue, `--bm-text-dim` neutral,
  `--bm-warning` amber, `--bm-danger` red, `--bm-success` green,
  to add: `--bm-purple-500`, `--bm-teal-600`
- Typography: Inter (UI), 12–14px for chat, 11px for chip text

---

## Surface 1 — Plan Checklist (sticky, above chat)

### What it replaces
Nothing — net-new surface. Today, when the user submits a complex
request, the chat just streams 🔹 lines as work happens with no upfront
sense of total scope.

### Entry point
Auto-appears after the user submits a message that the backend's
`TaskDecomposer.decompose_request()` resolves to ≥2 sub-tasks. For
single-task queries, this surface does NOT render — the chat works as
today.

### Layout

```
┌─ Plan ─────────────────────────── 2 of 5 done · ↻ ─[edit]─[hide]─┐
│ ✅  Quality control on FASTQ files                                │
│ ✅  STAR alignment (45s)                                          │
│ 🔵  Differential expression analysis  ← running…                  │
│ ⚪  Pathway enrichment                  ⇄ parallel with below     │
│ ⚪  GO term annotation                  ⇄ parallel with above     │
└───────────────────────────────────────────────────────────────────┘
```

Items can be nested (sub-tasks indent under their parent):

```
│ 🔵  Variant calling  ← running…                                   │
│      ✅  Reference indexing                                        │
│      🔵  BWA-MEM alignment                                         │
│      ⚪  GATK HaplotypeCaller                                      │
```

States:
- ⚪ pending
- 🔵 running (pulsing soft blue)
- ✅ done (green check)
- ⚠️ warning (amber, e.g. QC flagged)
- ❌ failed (red, with inline "Retry" / "Skip" buttons)
- ⏭️ skipped (grey, struck through)

The checklist is **sticky** at the top of the chat scroll, ~80px tall
when collapsed, expands to ~240px max (scrolls internally beyond that).

### Data Source
`POST /api/research/plan` (new endpoint) — body: `{query, session_id}`
Returns:
```
{
  plan_id: str,
  items: [{
    id, title, status, parent?, parallel_group?, invocationId?,
    estimated_duration_s, depends_on: [item_id]
  }],
  total_estimated_duration_s,
  created_at,
}
```

Live updates via existing `/api/workflows/{inv}/events` SSE, plus a new
`/api/research/plan/{plan_id}/events` SSE for plan-level updates.

### Behaviour
- **Tick in place**: when a 🔹 event arrives with `invocationId` matching
  an item, that item's status updates IN PLACE (no new row added). The
  pulse/check animation runs ~200ms.
- **Edit before run**: before any task starts running, the checklist
  shows an `[edit]` button. Clicking it lets the user drag items to
  reorder, click an item to remove it, or click `+ Add step` to insert
  one. **A 10s auto-proceed countdown** runs while the user is in edit
  mode — if no edit action in 10s, the plan locks and execution starts.
  See [Auto-Proceed Conventions](#auto-proceed-conventions).
- **Parallel groups**: items with the same `parallel_group` show the
  ⇄ glyph and a thin connector line between them. They tick to "running"
  simultaneously.
- **Hide**: collapses to a single-line "Plan: 3 of 5 done" pill at the
  top of chat. Click to re-expand.
- **Failure path**: a failed item flashes red, expands to show the
  failure reason (1–2 sentences from the backend), and offers
  "Retry" / "Skip" / "Ask DeepAgent" inline buttons. Other items keep
  running unless they depend on the failed one (depends_on chain).
- **Completion**: when all items reach a terminal state, the checklist
  auto-collapses to the single-line pill and surfaces a chat line:
  "Plan finished — 4 of 5 succeeded, 1 skipped."

### Chat card variant
None — this is always the sticky top surface, never an inline chat card.

---

## Surface 2 — Speaker-Pilled Chat Lines

### What it replaces
The current undifferentiated stream of 🔹 italic lines
(`chat-message.tsx` `metadata.type === 'workflow_progress'`).

### Entry point
Every 🔹 line in the chat. This is a per-line decoration, not a separate
component.

### Layout

```
🔹 PLAN   Decomposed your request into 3 phases.            · 4:22 PM
🔹 WF     Got it — starting your workflow now.              · 4:22 PM
🔹 WF     Step 2/5: STAR alignment…                         · 4:23 PM
🔹 QC     ⚠ QC flagged hERG = 0.62 (threshold 0.5).         · 4:24 PM
🔹 LOOP   Trying again with logp_max=4.5, mw_max=480.       · 4:24 PM
🔹 AGENT  Investigating why FASTQ format check failed.      · 4:25 PM
🔹 FIND   Pilot looks good. Ready for full run?             · 4:25 PM
```

Each line layout:
```
[🔹] [SPEAKER_PILL] [italic friendly message]                  · time
```

Speaker pill is 4–5 chars, monospace, 10px, in a pill background tinted
by speaker color (see [Speaker Taxonomy](#speaker-taxonomy)).

### Data Source
Extends the existing chat_progress SSE payload — narrator emits include
a `speaker` field already derivable per kind (`workflow.*` → 'workflow',
`workflow.qc_*` → 'qc', etc.).

### Behaviour
- **Color coding**: pill background uses speaker's oklch token at low
  opacity (~12%). Pill text uses the same token at full saturation.
  See [Speaker Taxonomy](#speaker-taxonomy).
- **Severity overrides**: QC speaker becomes red when the message has
  `kind === 'workflow.qc_gate_blocked'`; amber for `qc_gate_warning`.
- **Same-speaker collapse**: 3+ consecutive same-speaker lines collapse
  into "WF — 5 updates" with a click-to-expand caret. The newest message
  is always shown; older ones hide behind the caret.
- **Hover**: hovering a pill shows a tooltip with the speaker's role
  ("Workflow executor", "Quality control gate", etc.) — accessibility +
  onboarding.

### Chat card variant
N/A — this is the chat lines themselves.

---

## Surface 3 — Phase Card → Expand to Sub-Trace

### What it replaces
The current phase card in the workflow panel
(`nextflow-workflow-viewer.tsx`) shows phase name + status + a small
expand chevron that today reveals only step files. Replace with a richer
expand that shows the LLM rationale, the live Nextflow events for that
phase, and the parameter decisions.

### Entry point
User clicks a phase card or its `[ⓘ]` info icon.

### Layout

Collapsed (today's state — unchanged):
```
┌─ STAR alignment ──────────────── ✅ done · 45s · 1.2M reads ──┐
└────────────────────────────────────────────────────────────────┘
```

Expanded (new):
```
┌─ STAR alignment ──────────────── ✅ done · 45s · 1.2M reads ──┐
│                                                                │
│ ▾ Why this step                                                │
│   STAR was selected over HISAT2 because your samples are       │
│   GRCh38 with average read length 150bp, which matches STAR's  │
│   optimal regime. Cited from rationale knowledge base.         │
│                                                                │
│ ▾ Live events (12)                                             │
│   🔹 WF  Submitted to AWS Batch (job 8f3e21…)                  │
│   🔹 WF  Container pulled (8s)                                 │
│   🔹 WF  Running on m5.4xlarge — 16 vCPU, 64 GB RAM            │
│   🔹 WF  Read input from s3://…/SRR123_R1.fastq.gz (2.4 GB)    │
│   …                                                             │
│   [Show all 12]                                                │
│                                                                │
│ ▾ Parameters used                                              │
│   --outSAMtype BAM SortedByCoordinate     [edited from default]│
│   --alignIntronMax 500000                  [default]            │
│   --runThreadN 16                          [default]            │
│   [Edit parameters and re-run]                                 │
│                                                                │
│ ▾ Cost                                                          │
│   Used: ~$0.32 (3 vCPU-hours)  ·  Est: $0.30                   │
└────────────────────────────────────────────────────────────────┘
```

### Data Source
`GET /api/workflows/{inv}/phases/{phase_name}/trace` (new endpoint)
Returns:
```
{
  phase_name: str,
  rationale: { text, source_url?, source_title? },
  events: [{ts, speaker, message, technical}],
  parameters: [{name, value, source: 'default'|'user'|'autoloop'}],
  cost: { used_usd, estimated_usd, vcpu_hours },
  outputs: [{file, size_bytes, s3_uri}]
}
```

### Behaviour
- **Inline expand** (NOT a modal) — the phase card grows downward to fit
  the content; other cards in the panel shift down accordingly.
- **Three collapsible sub-sections** (Why this step / Live events /
  Parameters / Cost). Each opens independently.
- **Live events** sub-section: same italic 🔹 styling as the chat
  stream, filtered to this phase. New events stream in real-time while
  this expansion is open.
- **Edit parameters and re-run** button: only enabled for completed or
  failed phases. Opens the existing global-params editor scoped to this
  phase, then re-runs from this phase forward.
- **One expanded at a time** (optional, configurable) — clicking a
  second phase auto-collapses the first.

### Chat card variant
None — this lives inside the workflow panel.

---

## Surface 4 — Run-vs-Run Comparison Card (inline in chat)

### What it replaces
Today, when the auto-loop produces a remediated run, a was→now diff
appears in the auto-loop panel. Generalize that diff to ANY two runs
(auto-loop pair, two pilots, two campaigns) and render it inline in
chat as a chat card.

### Entry point
Three pathways:
1. **User asks**: "Compare run X with run Y" in chat.
2. **Auto-loop completes**: backend auto-emits the comparison card after
   the second run finishes.
3. **Pilot completes** with a previous pilot in the same session: chat
   offers "Compare with previous pilot? [Yes / No]" with a 10s
   auto-proceed defaulting to No.

### Layout

```
┌─ Compare runs ─ Run A vs Run B ───── 🏆 Run B preferred (high) ─┐
│                                                                  │
│   Metric             │  Run A         │  Run B         │  Δ     │
│  ────────────────────┼────────────────┼────────────────┼────────│
│   Runtime            │  12m 04s       │  9m 18s        │ −23%   │
│   Peak memory        │  31 GB         │  29 GB         │ −6%    │
│   hERG               │  0.62 ❌       │  0.38 ✅       │ −0.24  │
│   Ames               │  positive ❌   │  negative ✅   │  fixed │
│   logP               │  4.1           │  3.2           │ −0.9   │
│                                                                  │
│  Parameters that differed                                       │
│   • logp_max:     5.5 → 4.5     [auto-loop]                     │
│   • mw_max:       550 → 480     [auto-loop]                     │
│   • model_seed:   42  → 123     [user]                          │
│                                                                  │
│  💡 Recommendation                                              │
│     Run B passes all 3 QC gates with similar resource cost.     │
│     Confidence: high (statistical Δ on hERG p < 0.01)           │
│                                                                  │
│   [Use Run B]   [Keep Run A]   [Show full diff]                 │
│                                                                  │
│   Auto-confirming Run B in 9s unless you act.                   │
└──────────────────────────────────────────────────────────────────┘
```

### Data Source
`GET /api/workflows/runs/{idA}/compare?with={idB}` (existing, needs
`parameterDifferences` populated — WC-7 test gap).

Response shape extended:
```
{
  runs: [ExecutionRunSummary, ExecutionRunSummary],
  metrics: [{name, valueA, valueB, delta, deltaPercent, qcStatusA, qcStatusB}],
  parameterDifferences: [{param, valueA, valueB, changedBy: 'user'|'autoloop'}],
  recommendation: {
    preferredRun: 1 | 2 | 'inconclusive',
    reason: str,
    confidence: 'low'|'medium'|'high',
    autoProceedDefault: boolean,  // true → 10s auto-pick
  },
  statSignificance?: [{metric, p_value, test_name}]
}
```

### Behaviour
- **Recommendation badge** in the header: 🏆 emoji + "Run X preferred
  (confidence)". Color: green if confidence=high, amber if medium, grey
  if low or inconclusive.
- **Metric table rows**: red ❌ for QC fail, green ✅ for pass; Δ column
  color-coded (green for improvement, red for regression, grey for
  neutral changes).
- **Parameter diffs**: only show changed params (max 6 by default,
  "Show all" if more). `[auto-loop]` or `[user]` tag indicates origin.
- **Auto-proceed**: if `autoProceedDefault: true` (high confidence and
  one run clearly better), the "Use Run X" button has a 10s countdown.
  Hovering pauses it; clicking any of the three buttons stops it.
  Auto-firing emits a `workflow.auto_proceeded` chat line:
  "No response — using Run B."
- **Show full diff**: expands inline to show ALL metrics and ALL
  parameters (not just the differing ones).

### Chat card variant
This IS the chat card variant — it always renders as an inline chat
message of `metadata.type === 'run_comparison'`. Not a separate panel.

---

## Surface 5 — Pilot-First Toggle (run footer + promotion card)

### What it replaces
Today the run footer shows only `[Confirm and run workflow]`. Adds a
sibling `[Run pilot first]` option, and adds a new promotion card that
appears in chat when the pilot completes.

### Entry point
- **Toggle**: always rendered on the run footer (workflow panel
  sticky bottom) when the workflow's cost estimate ≥ $5, or when the
  AI assistant emits `pilot_run_suggested: true`. Below $5, hidden by
  default but accessible via a "More options" expand.
- **Promotion card**: auto-appears in chat when a pilot run reaches
  terminal state.

### Layout — Toggle (run footer)

```
┌─ Run footer ─────────────────────────────────────────────────────┐
│                                                                   │
│  ◉ Pilot first      ⚪ Full run only                              │
│  └─ 10% of samples (12 of 120), random ▾                          │
│                                                                   │
│  Pilot:   ~5 min,  ~$0.50  (vs. full: ~45 min, ~$8.20)            │
│                                                                   │
│  [Run pilot first ▶]    [Skip — run full directly]                │
└───────────────────────────────────────────────────────────────────┘
```

### Layout — Promotion card (inline chat card after pilot completes)

```
┌─ 🔬 Pilot done ─────────────────────────────────── all QC passed ─┐
│                                                                    │
│  Pilot ran on 12 samples in 4m 38s · cost $0.47                   │
│                                                                    │
│  QC summary                                                        │
│   ✅  FastQC      all 12 samples passed                            │
│   ✅  Alignment   ≥95% mapped (mean 97.2%)                         │
│   ✅  Strand      auto-detected reverse, confidence 0.99           │
│                                                                    │
│  Ready for the full run on 120 samples?                            │
│   Estimated: 45 min · $8.20                                        │
│                                                                    │
│   [Run full pipeline ▶]   [Adjust parameters]   [Stop here]        │
│                                                                    │
│   Defaults to "Stop here" in 10s — full runs need your explicit OK│
└────────────────────────────────────────────────────────────────────┘
```

If pilot QC failed:

```
┌─ 🔬 Pilot done ─────────────── ⚠ QC gates triggered ─────────────┐
│                                                                    │
│  Pilot ran on 12 samples in 4m 12s · cost $0.41                   │
│                                                                    │
│  QC summary                                                        │
│   ❌  Strand   detected as unstranded, but params said 'reverse'   │
│   ⚠   Mapping  only 41% reads aligned — likely sample mix-up      │
│                                                                    │
│  💡 The auto-loop suggests:  --strandedness unstranded            │
│                                                                    │
│   [Apply fixes and re-pilot]   [Adjust manually]   [Stop here]    │
│                                                                    │
│   Defaults to "Stop here" in 10s — full run not advisable yet.    │
└────────────────────────────────────────────────────────────────────┘
```

### Data Source
- Existing: `is_pilot=true` + `parameters.dataScope: {fraction, samplingStrategy}` in `POST /api/nextflow/execute`
- New (optional): `POST /api/research/cost_estimate` body `{workflow_id, dataScope?}` → `{est_usd, est_minutes, breakdown}`
- New narrator events:
  - `workflow.pilot_started` → "Running a quick pilot on N samples first."
  - `workflow.pilot_completed` → "Pilot done. All QC passed."
  - `workflow.pilot_failed_qc` → "Pilot stopped — QC gates triggered."
  - `workflow.pilot_promoted` → "Promoted to full run on N samples."

### Behaviour
- **Default ON** when cost estimate ≥ $5 OR `pilot_run_suggested: true`.
- **Sampling strategy dropdown**: `random` (default), `stratified`
  (requires choosing a strata column), `first_n`.
- **Cost estimate shown side-by-side** (pilot vs. full) so user sees the
  trade explicitly.
- **Promotion card auto-proceed**: defaults to **"Stop here"** in 10s
  (NOT to "Run full") — the explicit philosophy is: full runs cost real
  money, require explicit opt-in. Different from the auto-proceed
  defaults elsewhere in the system.
- **"Apply fixes and re-pilot"**: re-runs the pilot with the auto-loop's
  suggested params; counts as the same "pilot" iteration.
- **Skip — run full directly** button (on the original toggle): if
  clicked, the chat shows a confirmation 🔹 line: "Skipping pilot —
  running full pipeline directly."

### Chat card variant
The promotion card IS a chat card (rendered as
`metadata.type === 'pilot_promotion'`). The toggle lives only in the
run footer.

---

## Speaker Taxonomy

Used by Surface 2 (chat lines) and Surface 4 (parameter-change origin
tags). Each speaker has a 4–5 char pill code and an oklch color token.

| Speaker | Pill | Token | When |
|---|---|---|---|
| Planner | `PLAN`  | `--bm-text-dim` (neutral grey) | TaskDecomposer emits, plan items tick |
| Workflow | `WF`   | `--bm-accent` (primary blue) | Nextflow lifecycle, step events |
| QC gate | `QC`   | `--bm-warning` (amber) / `--bm-danger` (red) | qc_gate_warning / qc_gate_blocked |
| Auto-loop | `LOOP` | `--bm-purple-500` *(new token)* | Auto-loop remediations, retries |
| Deep Agent | `AGENT` | `--bm-teal-600` *(new token)* | DeepAnalysisAgent reasoning, suggestions |
| Findings | `FIND` | `--bm-success` (green) | Analysis output, methods report |
| User | `YOU` | existing bubble | User messages (unchanged) |

---

## Auto-Proceed Conventions

This system uses **10s auto-proceed countdowns** consistently on blocking
decisions. The conventions:

| Decision | Default action on timeout | Rationale |
|---|---|---|
| QC gate inline card | "Keep current" (dismiss) | Workflow continues; safest no-op |
| Low-confidence "Confirm anyway" | "Confirm anyway" | The workflow is the user's intent; just proceed |
| Plan checklist edit mode | "Lock and run" | Same as user clicking Run |
| Comparison card (high-confidence rec) | "Use preferred run" | The recommendation IS the safe call |
| Comparison card (medium/low confidence) | **No auto-proceed** — sits indefinitely | Don't pick wrong when uncertain |
| Pilot promotion card (QC passed) | **"Stop here"** (NOT run full) | Full runs cost real money, require explicit opt-in |
| Pilot promotion card (QC failed) | "Stop here" | Don't waste full-run spend on broken data |

When auto-proceed fires, a 🔹 chat line is emitted:
"No response — {decision} automatically."

---

## Information Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│ Header — workflow title + Cancel / Pause / Resume                │
├──────────────────────────────────────────────────────────────────┤
│ Surface 1: Plan checklist (sticky, when ≥2 sub-tasks)            │
├──────────────────────────────────────────────────────────────────┤
│ Chat stream                                                      │
│   ▶ Surface 2: speaker-pilled 🔹 lines                          │
│   ▶ Surface 4: Run-vs-Run comparison cards (inline)             │
│   ▶ Surface 5: Pilot promotion card (inline)                    │
├──────────────────────────────────────────────────────────────────┤
│ Workflow panel (existing)                                        │
│   ▶ Surface 3: phase card → expand to sub-trace                 │
├──────────────────────────────────────────────────────────────────┤
│ Run footer                                                       │
│   ▶ Surface 5: Pilot-first toggle                               │
│   [Confirm and run workflow]                                     │
└──────────────────────────────────────────────────────────────────┘
```

---

## Design Notes for Claude Design

### Tone
Calm, factual, on the user's side. Not chatty. The chat lines should
sound like a colleague narrating: short sentences, plain English, no
emoji-heavy exuberance. No "🚀 Awesome!". Yes "Workflow done. 5 of 5
steps succeeded."

### Typography
- Plan checklist titles: 13px medium (Inter)
- Speaker pills: 10px monospace, uppercase
- Chat 🔹 lines: 12px italic regular
- Comparison card numbers: 13px tabular-nums (alignment matters)
- Phase card expanded body: 13px regular
- Cost amounts: 13px tabular-nums + monospace for currency

### Key color usage
- Plan checklist status: ⚪ pending (grey), 🔵 running (pulsing
  `--bm-accent`), ✅ done (`--bm-success`), ⚠️ warn (`--bm-warning`),
  ❌ failed (`--bm-danger`), ⏭️ skipped (`--bm-text-dim`)
- Speaker pills: see [Speaker Taxonomy](#speaker-taxonomy)
- Comparison card: green Δ for improvement, red Δ for regression, grey
  for neutral
- Pilot promotion: green border when QC passed, amber when QC failed
- Auto-proceed countdown text: `--bm-text-dim`, never red (it's not an
  alarm — it's a courtesy)

### Whitespace + density
- Plan checklist items: 28px row height when collapsed
- Chat 🔹 lines: 24px row height; same-speaker collapse to 1 row when
  count > 3
- Comparison card: 16px gutter, 12px row pitch in the metric table
- Phase card expanded: 16px section headers, 4px line-height inside
  events sub-section

### Motion
- Plan item ✅ check: 200ms scale-in
- Speaker pill on new line: 150ms fade-in
- Auto-proceed countdown: tick once per second, no animation on the
  number itself (countdowns that "spin" are distracting)
- Phase card expand: 240ms ease-out height transition
- Comparison card recommendation badge: no entrance animation —
  appears in place

### What NOT to do
- **No wizard "Next → Next → Next"** — every decision card has 2–3
  buttons inline, no multi-step flows
- **No modal dialogs** — everything inline. Modals interrupt the
  conversational flow
- **No live-tailing of raw stdout** anywhere in chat. The chat is
  narrated, not a terminal
- **No dashboard tab** for comparison or experiments. They live inline
  in the chat that initiated them
- **No DAG visualization** for the plan checklist. Indentation +
  ⇄ parallel-group glyph is enough; don't draw arrows
- **No emoji-as-button-icon** — keep `🔹` as the chat-line marker and
  `🔬` only on the pilot card; everything else uses lucide-react icons
- **No "skeleton loader that never resolves"** — if a plan item is
  waiting, show what it's waiting on (the dependency)
- **No "auto-proceeded silently"** — every auto-proceed must surface
  a 🔹 chat line. The user must always know what happened

### Accessibility
- All speaker pills get an `aria-label` with the role name in full
- Auto-proceed countdowns are NOT the only way to know time is passing
  — also include "Auto-confirming in 9s" as visible text
- Comparison card recommendation badge: color + emoji + text (don't
  rely on color alone)
- Plan item status: emoji + text label ("running…", "done") — color is
  a cue, not the signal

---

## API Endpoints Needed

| Endpoint | Method | Status | Purpose |
|---|---|---|---|
| `/api/research/plan` | POST | **new** | Decompose query into plan items |
| `/api/research/plan/{plan_id}/events` | SSE | **new** | Plan-level updates |
| `/api/workflows/{inv}/phases/{name}/trace` | GET | **new** | Phase rationale + events + params |
| `/api/workflows/runs/{a}/compare?with={b}` | GET | **fix** | Add `parameterDifferences` population (WC-7) |
| `/api/research/cost_estimate` | POST | **new** (optional) | Pilot vs. full cost preview |
| `/api/nextflow/execute` with `is_pilot=true` | POST | exists | Pilot mode dispatch (already honored) |
| `/api/workflows/{inv}/events` | SSE | exists | Workflow chat-progress (extends with `speaker` field) |

---

## Telemetry Events to Track

Per surface, the events that fire for product analytics:

- **Surface 1 (Plan)**: `plan.shown`, `plan.edited`,
  `plan.locked_by_user`, `plan.auto_locked_by_timeout`,
  `plan.item_clicked`, `plan.item_failed`, `plan.item_retried`,
  `plan.item_skipped`, `plan.completed`
- **Surface 2 (Speakers)**: `speakerline.shown`,
  `speakerline.collapsed`, `speakerline.expanded`
- **Surface 3 (Phase expand)**: `phase.expanded`, `phase.event_clicked`,
  `phase.params_edited`, `phase.rerun_from_here`
- **Surface 4 (Comparison)**: `comparison.shown`,
  `comparison.recommendation_accepted`,
  `comparison.recommendation_overridden`,
  `comparison.auto_proceeded`, `comparison.full_diff_expanded`
- **Surface 5 (Pilot)**: `pilot.toggle_on`, `pilot.toggle_off`,
  `pilot.started`, `pilot.completed_qc_pass`,
  `pilot.completed_qc_fail`, `pilot.promoted_to_full`,
  `pilot.stopped_here`, `pilot.applied_fixes_and_repiloted`

---

## E2E Coverage Required

| Surface | New test file | Reuses |
|---|---|---|
| 1 | `e2e/research-plan-checklist.e2e.ts` | — |
| 2 | (extends `workflow-chat-progress-comprehensive.e2e.ts`) | speaker pill assertions |
| 3 | `e2e/workflow-phase-expansion.e2e.ts` | — |
| 4 | `e2e/workflow-run-comparison.e2e.ts` | fixes WC-7 |
| 5 | `e2e/workflow-pilot-first.e2e.ts` | — |

Each E2E test must:
1. Seed a session via localStorage (existing pattern)
2. Assert the surface renders correctly via data-testid
3. Capture a full-page screenshot for visual audit
4. Verify auto-proceed countdowns fire after their timeouts
5. Verify chat narration lines appear with the right speaker pills

---

## Open Questions for Design Review

1. **Plan editability** — should users edit the plan before run? Or is
   that scope creep? *Recommend yes, with 10s auto-lock.*
2. **Same-speaker line collapse** — collapse after 3 consecutive? Or
   show all and let user scroll? *Recommend collapse after 3.*
3. **Comparison card placement** — inline mid-chat vs. side panel?
   *Recommend inline.*
4. **Pilot default** — auto-ON for cost ≥ $5, or always opt-in?
   *Recommend auto-ON above the threshold.*
5. **Phase expansion** — modal vs. inline? *Recommend inline.*
6. **Speaker pill placement** — before or after the 🔹? *Recommend
   after the 🔹, before the message text.*
7. **Comparison auto-proceed threshold** — what counts as "high
   confidence" that justifies auto-using the preferred run? *Recommend
   confidence === 'high' AND statSignificance present AND p_value < 0.05.*

---

## Out of Scope (Explicitly Deferred)

- Multi-tab dashboard for all of a user's recent runs (W&B-style)
- Cross-session comparison (compare runs from different chats)
- Statistical significance UI beyond a single p-value badge
- Long-term experiment tracking / lab notebook integration
- Plan templates / "save this plan for next time"
- Drag-and-drop plan editing with dependency graph rewiring
- Per-phase real-time CPU/memory plots (a different observability
  surface)

---

## Decision Gate

This is the gate before any code lands. Please review:
- The 7 open questions
- The IA sketch (which surfaces share the screen)
- Speaker taxonomy
- Auto-proceed default conventions table
- "What NOT to do" list

After approval, the engineering doc
`docs/20260515_RESEARCH_AGENT_UX_REQUIREMENTS.md` has the implementation
plan, rollout order, and feature-flag conventions.
