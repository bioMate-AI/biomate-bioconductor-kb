# Flexible Chain Execution — Design

**Date:** 2026-07-23
**Status:** Design (grounded in current code); phased plan proposed, not yet built.
**Related:** `docs/20260723_E2E_USECASE_AUDIT_CLINICAL_PBPK.md` (panel run-dispatch
root cause), `docs/20260720_MG_STRATIFICATION_ADMET_PBPK_TUTORIAL.md`.

---

## 1. The vision

A chain should be **a steerable plan, not a fixed program.** The user decides how
to execute it. Four modes + a recommendation layer:

| Mode | User intent | Execution policy |
|---|---|---|
| **Run whole** | "Run it" | Auto — each step's output feeds the next; halt only on failure / QC gate |
| **Step-by-step** | "Run, but let me review between steps" | Gated — run step N → show outputs + AI read → wait for *approve / modify / stop* |
| **Subset** | "Just do steps 2 and 3" | Partial — run only selected steps (needs upstream inputs supplied or from a prior run) |
| **Divergent path** | "Swap step 2 for X" / "add a QC step" / "go another way" | Edit-then-run — mutate the plan, re-validate connections, continue |

**Recommendation layer:** the system *proposes* a chain (never mandates). The user
accepts as-is / edits / rejects. Post-run, it can recommend the next step too.

**Design principle (user, 2026-07-23):** *"chat + edit, if feasible. No solution
will be absolutely perfect for all needs."* → path modification is **hybrid**:
conversational (LLM re-plans) for open-ended changes, structured (UI controls) for
the common well-typed operations. Accept that neither covers 100%.

---

## 2. Current state — two disconnected paradigms already coexist

The MG stratification demo revealed that BioMate already implements chaining **two
different ways**, which have never been unified:

### Paradigm A — emergent / conversational chaining (the MG demo)
Sequential, human-gated workflows where the system recommends the next step. This
is how the MG tutorial actually runs:
- Turn 1: `GSE227835` → `nf-core/differentialabundance` (DESeq2), pre-staged
  pseudobulk data (`galaxy-assistant.ts:8057-8064`).
- DESeq2 completes → `chain_suggestion` SSE proposes enrichGO
  (`nextflow-workflow-viewer.tsx:2154`).
- Turn 2: user replies "Yes" → `clusterprofiler` enrichGO, gene list auto-set
  (`galaxy-assistant.ts:8067-8071`).
- Turn 3: user pastes iptacopan SMILES → ADMET.

Evidence — the demo is implemented across **5+ harnesses, all turn-by-turn** except
one parallel variant:
| Harness | Entry / data path | Paradigm |
|---|---|---|
| `e2e/test_mg_demo_v2.mjs` | chip embeds pre-staged S3 URIs | turn-by-turn, "Yes" to enrichGO suggestion |
| `e2e/test_mg_demo_chip.mjs` | real index chip attaches 3 public CSVs | turn-by-turn (file-attachment entry) |
| `e2e/test_mg_demo_marketing.mjs` | biomate.ai chip → `?q=…&demoFiles=mg_demo` handoff | turn-by-turn (marketing entry) |
| `e2e/test_mg_demo_parallel.mjs` | 3 browser contexts | parallel-independent (DESeq2 ∥ enrichGO ∥ ADMET) |
| `e2e/diag_mg_{chat,manual,withfiles}.mjs` | with/without attachments | diagnostics |

**Strength:** flexible, human-in-loop, path-modifiable by chat.
**Gap:** no explicit plan object — you cannot say "run all three as one pipeline",
and the chain isn't a first-class, editable artifact.

### Paradigm B — formal pipeline / chain object
An explicit `workflow_type: 'pipeline'` (or `'chain'`) artifact with `pipeline_steps`
/ `chain_steps` and connections. E.g. `ADMET + PBPK → Virtual Patient Dose
Optimization` (`workflow_type:'pipeline'` set in `galaxy-assistant.ts:4614/4912/5083`;
`'chain'` in `routes.ts:11416`).

**Strength:** explicit plan, one-click whole-run, per-step approval gate exists.
**Gap:** the **panel run is a no-op** (see §4), and the panel offers no per-step
interaction.

**These two paradigms should collapse into ONE editable plan + policy model.**

---

## 3. What already exists (grounded, with anchors)

More of the target is built than expected — mostly on the **chat-card** side:

| Capability | Chat card | Right panel | Anchor |
|---|---|---|---|
| Run whole | ✅ `PipelineListView` (no gate) → "Confirm & Run Pipeline"; `WorkflowChainPlan` → `onRunChain` | ❌ no-op bug | `chat-message.tsx:759-817`; `pipeline-list-view.test.tsx:36` |
| Step-by-step gated | ✅ `approvalGate` → "Confirm & Run Step 1", then sequential per-step approve buttons | ❌ | `pipeline-list-view.test.tsx:41-73` |
| Run step 1 then halt | ✅ `handleRunPipeline` submits with `endAtStep: 0` | — | `chat-with-artifacts.tsx:1216-1253` |
| Approve next step | ✅ `handleApprovePipelineStep` → `resumeWorkflowChain({startFromStep, endAtStep})` | — | `chat-with-artifacts.tsx:1255-1310` |
| Path modify (chat) | ✅ `onModifyStep → onAdjustViaChat` (LLM re-plans) | partial (`onAdjustViaChat` wired) | `chat-message.tsx:787` |
| Recommend next step | ✅ `chain_suggestion` + `proactive_suggestion` SSE | ✅ same SSE | `nextflow-workflow-viewer.tsx:2154, 2174` |
| Chain state sync | ✅ poll `chain_run_id`, `syncPipelineStepsFromChain` | — | `chat-with-artifacts.tsx:1312-1358` |

**Missing everywhere:**
- **Subset selection** — no way to pick "just steps 2 and 3" (no checkboxes / range).
- **Structured path editing** — no swap / insert / remove / reorder UI.
- **Unified plan object** — chain state is split between chat-message metadata
  (`pipeline_steps`/`chain_steps`) and the Galaxy `chain_run_id`; the panel keeps
  its own single-workflow view. No single source of truth shared by chat + panel.

---

## 4. The blocking bug (Phase 0 — fix first)

The right panel renders **every** workflow through the single-workflow
`NextflowWorkflowViewer`; its `onExecute` (`chat-with-artifacts.tsx:2302-2318`)
**always calls `handleRunWorkflow(panelWorkflow, [])`** with no `workflow_type`
check. For a pipeline/chain, `handleRunWorkflow` (`:937`) sees no `nextflow_path`
→ `isNextflow=false` (`:956`); `steps=[]` → the guard at **`:959`** fires →
`console.error` + `setIsWorkflowRunning(false)` + silent `return`. No run, no error
— the greyed-button no-op observed in the PBPK E2E.

**Fix (minimal, mirrors `chat-message.tsx` dispatch):** in the panel `onExecute`,
branch before defaulting:
```js
if (panelWorkflow?.workflow_type === 'pipeline') return handleRunPipeline(panelWorkflow);
if (panelWorkflow?.workflow_type === 'chain')    return handleRunChain(panelWorkflow);
// else → existing single-workflow handleRunWorkflow path
```
"No configurable parameters" on a pipeline is correct — params live per sub-step.

---

## 5. The unifying model — chain plan + execution policy

Introduce one persistent **ChainPlan** object, shared by chat card and panel:

```
ChainPlan {
  id, name, domain, description,
  steps: [ { id, workflow_name, nextflow_path, params, status,
             uses_step_id, uses_description, selected } ],   // selected → subset
  connections: [ { from_step, from_output, to_step, to_input } ],
  policy: 'auto' | 'gated' | 'subset',
  chain_run_id?                                              // Galaxy-side run id
}
```

Execution is a **policy over the plan**, not a separate code path:
- `auto` → submit whole (existing `handleRunChain` / `submitWorkflowFromArtifact`).
- `gated` → `handleRunPipeline` (endAtStep:0) then `handleApprovePipelineStep` per
  step (both already exist).
- `subset` → submit only `steps.filter(selected)`, validating each selected step's
  upstream inputs are satisfied (from a prior run or user-supplied).

Both the MG emergent flow and the formal pipeline become **the same ChainPlan** —
the difference is just the policy and whether the plan was authored up-front or
grown turn-by-turn from `chain_suggestion`.

Path modification (hybrid, per user steer):
- **Chat**: `onModifyStep → onAdjustViaChat` → assistant returns an updated
  ChainPlan (already wired; keep for open-ended edits).
- **Structured** (where feasible): `PipelineListView` gains swap (dropdown of
  compatible workflows) / insert / remove / reorder + subset checkboxes. On any
  structured edit, **re-validate `connections`** (does `stepN.output` still satisfy
  `stepN+1.input`?) and surface a warning if a connection breaks — do not silently
  run a broken plan.

---

## 6. Phased plan

- **Phase 0 — unblock (small):** fix the panel run-dispatch bug (§4). Makes
  "run whole" work from the panel at all. tsc + vitest + PBPK-chain E2E to green.
- **Phase 1 — unify state (medium):** introduce `ChainPlan` as the single source of
  truth; make chat card and panel both read/write it. Collapse `pipeline_steps` /
  `chain_steps` / panel single-view into one. Persist across turns.
- **Phase 2 — subset + conversational modify (medium):** subset checkboxes in
  `PipelineListView`; `policy: 'subset'` submission with upstream-input validation.
  Harden `onModifyStep` round-trip so an LLM re-plan updates the ChainPlan in place.
- **Phase 3 — structured edits + connection re-validation (larger):** swap / insert /
  remove / reorder controls; connection re-validation with break warnings; "recommend
  a chain" surface that lets the user accept / edit / reject before running.

Explicitly out of scope for now (accept imperfection): arbitrary DAG branching
(parallel forks/joins beyond the existing parallel-independent harness), and
fully automatic connection repair on edit (warn, don't auto-fix).

---

## 7. Open questions — RECOMMENDATIONS (2026-07-23)

### Q1 — panel edits vs monitor → **Chat card = editor; Panel = monitor + whole-run trigger**
Split responsibilities, do not duplicate:
- **Chat card (`PipelineListView` / `WorkflowChainPlan`)** owns *structural* editing —
  swap / insert / remove / reorder / subset — and conversational modify. It already
  hosts `onModifyStep` and the approval gate; keep all plan authoring there.
- **Panel (`NextflowWorkflowViewer`)** stays the run-monitor: live per-step status,
  outputs, findings, QC — plus the **whole-run trigger** (Phase 0 fix) and **per-step
  param edits** (it already has the per-phase param panel).
- **Rationale:** two structural-edit surfaces would diverge and double the
  state-sync burden. One editor + one monitor is the least-moving-parts design.
  Boundary: *structure* → chat card; *params & monitoring* → panel.

### Q2 — subset with missing upstream → **Auto-offer to run the prerequisite; allow manual override**
When the user selects step N but a connection feeds it from an unran step M:
- Default: prompt *"Step N needs output from Step M. Run Step M first?"* with
  **[Run M→N]** (recommended) and **[I'll provide the input]**.
- Do NOT silently require a hand-supplied intermediate (users rarely have the
  exact intermediate file/format), and do NOT auto-force the prerequisite either —
  offer it. This honours "it's up to the user."
- Guard: if the user supplies input manually, validate it against the
  `connection.to_input` type/format before running.

### Q3 — ChainPlan persistence → **Phase 1: single chat-session object; later: durable server row for resumability**
Two-step:
- **Now (Phase 1):** collapse the duplicated per-message `pipeline_steps` /
  `chain_steps` into ONE `ChainPlan` object in chat-session state (today it is
  copied across messages and reconciled via `syncPipelineStepsFromChain` —
  fragile). Single source of truth, cheap.
- **Later:** persist the `ChainPlan` server-side alongside the existing Galaxy
  `chain_run_id`, following the `RunStateStore`/Redis pattern (see CLAUDE.md
  "Run-State Persistence"). This is what enables **"resume a half-run chain
  later"** — a durable plan independent of the chat transcript.
- **Rationale:** chat metadata alone can't survive session loss or support
  resume; but a full server table is premature before the object model settles.
  Consolidate the shape first, durably persist it second.
