# BioMate Research-Agent UX — Requirements & Design

**Date:** 2026-05-15
**Author:** integration/next-phase session
**Status:** Draft for Claude design review (no implementation yet)
**Related:**
- `docs/20260512_GALAXY_DEV_CAPABILITIES_AND_DEEP_AGENT_INTEGRATION.md`
- `docs/20260514_CHAT_PROGRESS_AUDIT.md`
- `docs/20260515_CONTROLS_AND_AUTOPROCEED_AUDIT.md`

---

## 1. Why this document

BioMate already has substantial *latent* capability for task decomposition,
parallel execution, pilot studies, and experimental comparison — but most
of it is not reachable from the current chat UX. Concurrently, the recent
chat-progress system (italic 🔹 lines) gives us a clean foundation to
surface those capabilities without a panel-heavy redesign.

This doc consolidates findings from three parallel investigations:
1. Inventory of what's already built (backend + orphan UI components)
2. UX patterns from auto-research agents in the CS domain
3. Gaps between code and current chat UX

It proposes a five-pattern extension that surfaces all the latent capability
through one coherent IA. **No implementation has started**; this doc is the
gate before that work.

## 2. Goals & non-goals

**Goals**

- Extend the existing chat + 🔹 progress model. Do not replace it.
- Surface task decomposition, parallel execution, pilot mode, and run
  comparison as a single coherent conversational flow.
- Borrow the strongest patterns from Deep Research / Devin / Sakana /
  AutoGen, adapted to BioMate's high-cost, gate-driven workflow domain.
- One IA pass that prevents the five patterns from colliding visually.

**Non-goals**

- Full DAG-canvas visualization (LangGraph Studio style). Keep the DAG
  implicit; surface only when a phase fails.
- A separate "agent terminal" pane (Devin/Manus style). BioMate's audience
  is wet-lab scientists; terminal-feel reduces perceived rigor.
- Replacing Nextflow-native step tracking. The workflow panel keeps its
  current structure; the chat narrates above it.

## 3. Inventory of latent capability

### 3.1 Task decomposition & parallel execution

| Item | Path | Status |
|---|---|---|
| `Task` dataclass + dependencies | `backend/lib/galaxy/ai/types.py:127` | Used internally |
| `TaskGraph` with topological sort | `backend/lib/galaxy/ai/types.py:227` | Used by workflow_optimizer |
| `TaskDecomposer` (LLM + template) | `backend/lib/galaxy/ai/task_decomposer.py:136` | **Orphan** — not called from chat |
| `AgentOrchestrator` (parallel specialists) | `backend/lib/galaxy/ai/agents/agent_orchestrator.py:113` | **Used** in workflow generation |
| `_identify_parallel_groups()` | `backend/lib/galaxy/ai/workflow_optimizer.py:113` | **Used** for runtime estimation; hints not surfaced |
| `TaskList` component | `frontend/client/src/components/task-list.tsx` | **Wired** for LangGraph generation tasks; not execution phases |
| Workflow chain API | `backend/lib/galaxy/webapps/galaxy/api/workflow_chain.py` | **Orphan** — no chat trigger |
| Soft query queue | `frontend/client/src/components/chat-interface.tsx:1479` | Active; queues messages while AI responds |

### 3.2 Pilot study mode

| Item | Path | Status |
|---|---|---|
| `is_pilot` request flag | `nextflow_executor.py:332` | Backend honors |
| `dataScope.fraction/strategy/...` | `frontend/shared/schema.ts:737` | Schema only |
| `pilot_run_suggested` AI emit | `routes.ts:3600` | Emitted but no consumer |
| `PilotExperimentPanel` component | `frontend/client/src/components/pilot-experiment-panel.tsx` | **Orphan** — never imported |
| Pilot narrator events | (none) | **Missing** |

### 3.3 Experimental comparison

| Item | Path | Status |
|---|---|---|
| `RunComparison` schema | `frontend/shared/schema.ts:974` | Defined |
| `experiments` table | `frontend/shared/schema.ts:121` | Schema; migrations exist |
| `GET /api/workflows/runs/:id/compare` | `frontend/server/routes.ts:9792` | Reachable, returns comparison |
| `storage.compareExecutionRuns` | `frontend/server/storage.ts:749` | Computes deltas, **missing `parameterDifferences`** |
| Experiment CRUD `/api/experiments*` | `routes.ts:11874+` | Reachable |
| Comparison view (in PilotExperimentPanel) | `pilot-experiment-panel.tsx:234-348` | **Orphan** |
| Comparison narrator events | (none) | **Missing** |

## 4. Reference systems & deltas

Compact mapping of the CS-domain patterns to BioMate adaptations.

| Source | Pattern borrowed | BioMate adaptation |
|---|---|---|
| OpenAI / Perplexity / Anthropic Deep Research | Streaming sub-question checklist edited in place during work | Plan checklist above the workflow panel, ticked off as 🔹 events arrive; ~5–10 items max |
| Sakana AI Scientist v2 | Cheap "sanity experiment" before full sweep | "Pilot first" toggle on run-confirmation; gated on QC; cost-delta vs. full |
| Devin / Cognition | Plan item → click → expanded sub-trace | Phase card → click → LLM rationale + Nextflow events + param decisions for that phase |
| AutoGen / Agent Laboratory | Multi-role transcript with speaker labels | Planner / Workflow / QC / Auto-loop / Findings speakers with consistent prefixes + colors |
| Weights & Biases sweep table | Diff highlight in run comparison | Two-column "Run A vs Run B" card inline in chat; reuse auto-loop was→now diff styling |

**What we explicitly don't copy:**
- Sakana's headless artifact dump — BioMate users want to steer mid-run
- Devin's free-form terminal pane — BioMate's typed workflow graph is more rigorous
- LangGraph Studio's full DAG — overwhelming for wet-lab audience

## 5. Five-pattern proposal

### Pattern A — Plan checklist

**Trigger.** When intent classification detects a non-trivial query
(`TaskDecomposer.decompose_request()` returns ≥2 tasks).

**Data contract.**
```ts
type PlanItem = {
  id: string;             // task.id from TaskDecomposer
  title: string;          // 1-line friendly description
  status: 'pending' | 'running' | 'done' | 'failed' | 'skipped';
  parent?: string;        // for nested sub-tasks
  parallel_group?: number; // tasks with the same group run concurrently
  invocationId?: string;  // links to a workflow run when applicable
};
type Plan = { items: PlanItem[]; root_query: string; created_at: number };
```

**Visual.** Renders ABOVE the chat scroll, sticky-top, ~80 px tall when
collapsed. One item per line: status pill + title + (if applicable)
"⇄ parallel group N" hint. Click to expand: sub-trace for that item.

**Interaction states.**
- Items tick from pending → running → done as 🔹 events match (by
  `invocationId` and/or `task.id`)
- A failed item flashes red, expands to show the failure reason +
  "Retry" / "Skip" buttons
- The checklist edits *in place* (does not append new copies)

**Telemetry.** `plan.created`, `plan.item_started`, `plan.item_completed`,
`plan.item_failed`, `plan.user_skipped_item`.

**Open question.** Do we let the user edit the plan (add/remove/reorder
items) before the first task starts? Devin says yes; Sakana says no.
**Recommend yes**, with a 10s auto-proceed if the user doesn't intervene.

### Pattern B — Role-prefixed progress lines

**Trigger.** Every 🔹 line emitted by any source.

**Data contract.** Extend the existing narrator event with a `speaker` field:
```python
speakers = Literal['planner', 'workflow', 'qc', 'autoloop', 'deepagent', 'findings', 'user']
```

**Visual.** Each 🔹 line gets a small speaker pill (4-letter cap, oklch
token per speaker) before the italic message:
- `PLAN` (planner) — neutral grey
- `WF`   (workflow) — primary blue
- `QC`   (qc gate)  — amber on warning, red on blocked
- `LOOP` (auto-loop) — purple
- `AGENT` (deep agent) — teal
- `FIND` (findings) — green

**Migration.** Backend `workflow_chat_narrator.emit()` adds a default
speaker per kind:
- `workflow.*` → 'workflow'
- `workflow.qc_*` → 'qc'
- `workflow.autoloop_*` → 'autoloop'
- `deepagent.*` → 'deepagent'
- new `plan.*` → 'planner'
- new `findings.*` → 'findings'

**Open question.** Do we deduplicate consecutive same-speaker lines?
Probably yes — collapse 3+ consecutive WF lines into "WF — N updates …
(click to expand)".

### Pattern C — Phase card expansion

**Trigger.** User clicks a phase card in the workflow panel.

**Data contract.** New endpoint
```
GET /api/workflows/{inv}/phases/{phase_name}/trace
  → { llm_rationale: str, nextflow_events: [...], params_decided: {...},
       cost_estimate: { vcpu_hours: float, est_usd: float } }
```

**Visual.** Phase card expands inline (not a modal) to show three
collapsible sub-sections: **Rationale**, **Events**, **Parameters**.
The events sub-section is the same 🔹 stream filtered to that phase.

**No new component** — extend the existing phase-card render in
`nextflow-workflow-viewer.tsx`. The current implementation already has
collapsible mechanics for QC settings.

### Pattern D — Run-vs-Run comparison card

**Trigger.** Three pathways:
1. User asks "compare run X to run Y" in chat
2. Auto-loop completes with a remediated run (current was→now diff,
   generalized)
3. Pilot run finishes → "Compare with previous pilot? [Y/N]" with 10s
   auto-proceed (defaults to no)

**Data contract.** Extend the existing `RunComparison` schema with:
```ts
{
  ...existing,
  parameterDifferences: Array<{
    param: string;
    run1Value: any;
    run2Value: any;
    auto_changed?: boolean;  // true if auto-loop changed it
  }>,
  recommendation: {
    preferredRun: 1 | 2 | 'inconclusive';
    reason: string;
    confidence: number;
  };
  statSignificance?: { metric: string; p_value: number }[];
}
```

The backend `compareExecutionRuns` currently misses `parameterDifferences` —
this is the WC-7 test gap. **Fix as part of this pattern's implementation.**

**Visual.** Two-column card inline in chat:
- Header: "Run A vs Run B" + recommendation badge (preferredRun)
- Metric grid: runtime / memory / quality deltas with color-coded Δ
- Parameter diffs: was → now per row, with `auto_changed` marker
- Footer: "Use preferred" button + 10s auto-proceed if recommendation is
  high-confidence

**Open question.** Do we render the comparison card inline (mid-chat) or
in a side panel? **Recommend inline** for consistency with the auto-loop
remediation card pattern; users already expect comparisons to live in the
narrative.

### Pattern E — Pilot-first toggle

**Trigger.** Always rendered on the run-confirmation modal/footer.

**Data contract.**
```ts
type PilotConfig = {
  enabled: boolean;
  fraction: number;        // 0.05–0.30
  samplingStrategy: 'random' | 'stratified' | 'first_n';
  // populated from existing dataScope schema
};
```

**Visual.** A pre-existing "Run" button gets a sibling "Run pilot first"
button when `pilot_run_suggested` is true OR the workflow has known
high-cost phases (e.g. AlphaFold3, RNA-seq with N>20 samples).

Cost preview rendered below: "Pilot: ~5 min, ~$0.50 · Full: ~45 min, ~$8.20".

**Promotion flow.** When the pilot completes:
1. Narrator fires `workflow.pilot_completed` → chat line
2. If QC gates pass, inline card appears: "Pilot looks good. Run full? \[Yes\] \[Adjust\]"
   with a 10s auto-proceed defaulting to **No** (user must opt in to spend
   the full $8.20)
3. If QC gates warn/block, the card defaults to "Adjust" not "Yes"

**New narrator events.**
- `workflow.pilot_started` → "Running a quick pilot on N samples first."
- `workflow.pilot_completed` → "Pilot done. {QC summary}. Ready for full run?"
- `workflow.pilot_promoted` → "Promoted to full run."
- `workflow.pilot_aborted` → "Pilot stopped — issues found, won't run the full pipeline."

**Open question.** Should "Run pilot first" be ON by default for all
high-cost workflows? **Recommend yes** above a $5 estimated cost threshold,
off below.

## 6. Information architecture

The chat is the spine. Around it:

```
┌─────────────────────────────────────────────────────────────────────┐
│ Header: workflow title + run controls (Cancel / Pause / Resume)     │
├─────────────────────────────────────────────────────────────────────┤
│ Plan checklist (sticky, Pattern A)                                  │
│   ☑ Quality control                                                 │
│   ☐ STAR alignment (running…)                                       │
│   ☐ Differential expression                                         │
├─────────────────────────────────────────────────────────────────────┤
│ Chat stream                                                         │
│   YOU:  Run RNA-seq on these samples                                │
│   BIOMATE: "Here's the plan — running quick pilot first."           │
│   🔹 PLAN  Decomposed into 3 phases                                 │
│   🔹 WF    Got it — starting your workflow now.                    │
│   🔹 WF    Step 1/3: FastQC…                                       │
│   🔹 QC    QC flagged hERG = 0.62 (threshold 0.5).                 │
│   🔹 LOOP  Trying again with logp_max=4.5.                         │
│   🔹 FIND  Pilot looks good. Ready for full run?                   │
│                                                                     │
│   [Run-vs-Run comparison card, Pattern D — inline]                  │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│ Workflow panel (existing) — phase cards expand per Pattern C        │
│   ☑ FastQC                                                          │
│   ☐ STAR (running)  ← click expands to events / rationale / params  │
├─────────────────────────────────────────────────────────────────────┤
│ Run footer: [Run pilot first (Pattern E)]  [Confirm and run]        │
└─────────────────────────────────────────────────────────────────────┘
```

Ownership of each surface:

| Surface | Owns | Reads |
|---|---|---|
| Plan checklist | New `<PlanChecklist>` component fed by `task_decomposer` output | 🔹 events to tick items |
| Chat stream | Existing `chat-interface.tsx` | Adds speaker pills (Pattern B) |
| Phase cards | Existing `nextflow-workflow-viewer.tsx` | Adds expand-to-trace (Pattern C) |
| Comparison card | New `<RunComparisonCard>` rendered inline as a chat message | `RunComparison` API |
| Pilot toggle | Existing run footer | `pilot_run_suggested` + cost estimator |

## 7. Speaker / role taxonomy + color tokens

| Speaker | Pill text | Color token (oklch) | Justification |
|---|---|---|---|
| planner | PLAN | `--bm-text-dim` (neutral) | Procedural, not loud |
| workflow | WF | `--bm-accent` (primary blue) | Highest-frequency speaker |
| qc | QC | `--bm-warning` (amber) / `--bm-danger` (red) | Severity-sensitive |
| autoloop | LOOP | `--bm-purple-500` | Distinct from QC/WF |
| deepagent | AGENT | `--bm-teal-600` | Tied to the diagnose card |
| findings | FIND | `--bm-success` (green) | Positive completion |
| user | YOU | existing user bubble | Unchanged |

## 8. Pilot-mode contract

| Aspect | Behavior |
|---|---|
| Default | ON for workflows with cost estimate ≥ $5; OFF below |
| Trigger | Always-visible "Run pilot first" toggle on run footer |
| Backend | Existing `is_pilot=true` + `parameters.dataScope` already honored |
| Sampling | Default `fraction=0.1`, `strategy='first_n'`; user can override |
| Gate | If pilot QC gates trigger blocking failures, full run does NOT auto-start. Auto-proceed defaults to "Adjust", not "Run full" |
| Cost | Cost estimate displayed for pilot AND full so user sees the trade |

## 9. Comparison card data contract

(See Pattern D, section 5.)

Backend implementation TODO: populate `parameterDifferences` in
`storage.compareExecutionRuns` by diffing the two runs' execution params.
Expected by E2E test WC-7 — currently missing.

## 10. E2E coverage matrix

| Pattern | New test file | Existing files extended |
|---|---|---|
| A — Plan checklist | `workflow-plan-checklist.e2e.ts` | — |
| B — Role-prefixed lines | — | `workflow-chat-progress-comprehensive.e2e.ts` (add speaker assertions) |
| C — Phase expansion | `workflow-phase-expansion.e2e.ts` | — |
| D — Comparison card | `workflow-run-comparison.e2e.ts` | WC-7 (fix `parameterDifferences`) |
| E — Pilot toggle | `workflow-pilot-first.e2e.ts` | — |

Visual audit screenshots required per pattern; video on for the chat-stream
patterns (A, B) to verify in-place edit + de-dup behavior.

## 11. Rollout & flagging

Each pattern gets a server-side feature flag:

- `BIOMATE_RESEARCH_AGENT_PLAN_CHECKLIST`
- `BIOMATE_RESEARCH_AGENT_SPEAKERS`
- `BIOMATE_RESEARCH_AGENT_PHASE_EXPAND`
- `BIOMATE_RESEARCH_AGENT_COMPARISON`
- `BIOMATE_RESEARCH_AGENT_PILOT_FIRST`

Ship order (each on its own dev-EC2 sync):
1. **B (Speakers)** — smallest change, mostly cosmetic, gives immediate readability win
2. **D (Comparison)** — fills the WC-7 gap, unblocks the orphan
   PilotExperimentPanel data
3. **E (Pilot toggle)** — depends on backend `is_pilot` (already there)
   and on D's comparison once promotion flow runs
4. **A (Plan checklist)** — bigger surface change, needs IA review on
   live dev
5. **C (Phase expansion)** — biggest workflow-panel diff, ship last

## 12. Open questions for review

1. **Plan editability before run** — users edit the decomposed plan?
   (Recommended: yes, with 10s auto-proceed.)
2. **Speaker line de-dup** — collapse N consecutive same-speaker lines?
   (Recommended: yes, after 3.)
3. **Comparison card placement** — inline mid-chat vs. side panel?
   (Recommended: inline.)
4. **Pilot-first default** — auto-on above $5 estimate?
   (Recommended: yes.)
5. **Phase expansion** — modal vs. inline? (Recommended: inline.)

## 13. What's NOT in this doc (deferred)

- Multi-tab dashboard for all of a user's recent runs (W&B-style)
- Cross-session comparison (compare runs from different chats)
- Citation panel for findings-channel speakers (deferred to a later
  knowledge-flow doc)
- Statistical significance UI (p-values, confidence intervals) on the
  comparison card — needs domain-expert input on what's appropriate
- Long-term experiment tracking / lab notebook integration

## 14. Decision gate

This doc is the gate before implementation. **Please review the five
patterns + the IA sketch + open questions** before any code lands.

After approval:
- Pattern B is ~½ day (cosmetic)
- Pattern D is ~1 day (backend gap fix + new card component + reuse PilotExperimentPanel)
- Pattern E is ~1 day (toggle + cost estimator + promotion flow)
- Pattern A is ~2 days (new component + plan endpoint + tick-update wiring)
- Pattern C is ~1 day (phase-card expand + new trace endpoint)

Total ~5.5 days of focused work to ship all five behind feature flags.
