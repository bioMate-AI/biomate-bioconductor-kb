# Dataset-injection gate — design (2026-06-13)

## Problem

Today `<session_datasets>` is unconditionally injected into the chat
prompt whenever `context.sessionDatasets.length > 0`. This wastes
tokens on pure knowledge turns ("what is BH FDR?") and risks
distracting the LLM into anchoring on irrelevant data.

A naive intent-category gate (skip if `intent.type ===
'research_question'`) fails because:

| Message | Classifier | Wrong call if you only look at intent |
|---|---|---|
| "What is BH FDR correction?" | `research_question` | **Skip** is wrong if the user is asking because the DEG run they just kicked off is confusing them |
| "How long will this take?" | `troubleshooting` | **Skip** is wrong — the answer depends on dataset size |
| "Show me a paper on limma" | `research_question` | **Skip** is right — but only because nothing in the conversation suggests they mean their data |
| "Run DESeq2" with no datasets attached | `workflow_generation` | **Inject** is empty — nothing to inject anyway |

**Intent category is not independent of conversation state.** The same
label produces different relevance depending on whether the user has
just attached a file, whether a workflow is running, what the last
assistant turn referenced, etc.

## Reframe

Instead of "is this intent X?", the gate asks:

> *"Is there a non-trivial chance the LLM's answer will reference the
> user's data or run?"*

This is a context-relevance judgment built from multiple signals.

## Signals

Each is a pure function over inputs that can be implemented and
tested in isolation. Signals are **monotonic** — every signal that
fires pushes us toward "inject"; only the absence of all positives
plus a default-off intent yields "skip."

| Signal | Decisive? | What it reads |
|---|---|---|
| `messageReferencesData(message, datasets)` | **Yes** — overrides intent | Word-boundary regex on "the dataset / file I uploaded / counts / matrix / metadata", filename substring match against attached `dataset.name`, dataset-id pattern match |
| `runStateRelevant(runState)` | **Yes** | A run is currently active OR the most-recent run completed in the last 60 s |
| `isShortFollowupAfterDataThread(message, history)` | **Yes** | Message is ≤ 6 words AND last assistant turn matched `lastAssistantTurnReferencedData` |
| `lastAssistantTurnReferencedData(history, datasets)` | **Strong** | Last assistant message text contains a dataset id, a filename from the attached list, or the literal `<session_datasets>` rendering |
| `historyShowsAnyDataDiscussion(history, datasets)` | **Moderate** | Any of the last 3 turns matches `messageReferencesData` or `lastAssistantTurnReferencedData` |
| `intentSuggestsData(intent.type)` | **Weak** | One of `workflow_generation`, `data_interpretation`, `parameter_optimization`, `experiment_design`, `methods_writing` |
| `pureAbstractKnowledgeIntent(intent.type)` | **Skip default** | One of `research_question`, `comparative_methodology`, `regulatory_compliance` — only matters when *no other signal* fired |

## Composition

```
function shouldInjectDatasets(input):
  if (datasets.length == 0) return SKIP          // nothing to inject

  if (messageReferencesData)        return INJECT // user named it
  if (runStateRelevant)             return INJECT // mid/just-after run
  if (isShortFollowupAfterDataThread) return INJECT
  if (lastAssistantTurnReferencedData) return INJECT

  if (intentSuggestsData && historyShowsAnyDataDiscussion) return INJECT

  if (pureAbstractKnowledgeIntent) return SKIP    // abstract Q with no data trail

  return INJECT                                    // conservative default
```

**Default-on**, not default-off. The gate's job is to spot
*confidently irrelevant* turns and skip those. False-skips are worse
than false-injects: a missing data block can cause the LLM to ask the
user to re-attach a file they already have; a redundant block just
costs a few tokens.

## Decisions to lock down

1. **Default behavior on uncertainty**: keep injecting. Skip only when
   every signal is silent AND intent is pure-abstract.
2. **Threshold**: any single positive signal → inject. No "weight 2"
   stacking — too brittle to tune.
3. **Cache behavior**: when injected, the block content is identical
   across turns until the dataset list mutates → Anthropic prompt
   caching makes per-call $$ cost nearly zero on a chain of turns.
4. **Audit**: log the gate decision + which signals fired per turn so
   we can review the precision/recall on real traffic.

## What's out of scope (this PR)

- **Outputs**: same gate framework applies to a future
  `<recent_run_outputs>` block, but outputs aren't surfaced today.
- **Per-dataset selection**: when only 1 of 5 attached datasets is
  relevant, today we inject all 5. A finer "which dataset" selector
  is a separate optimization.
- **Re-injection on cache miss**: if Anthropic loses cache continuity
  and re-bills the block, that's a billing-layer concern not a gate
  concern.

## Audit plan

After deploy, for the first 100 production turns:

1. Tap the gate-decision log; count skipped vs injected.
2. For 20 random skipped turns: read the message + intent + history,
   manually score "did the LLM need the datasets?"
3. For 20 random injected turns where pure-abstract intent fired but
   another signal forced inject: check whether the dataset reference
   actually helped.
4. Adjust signals (regex tightening, history window) based on errors.
5. Document the result in a follow-up note.

## Files

- `frontend/server/dataset-injection-gate.ts` — pure functions, no IO.
- `frontend/server/dataset-injection-gate.test.ts` — per-signal unit
  tests + integration coverage.
- `frontend/server/galaxy-assistant.ts` — call site in
  `sessionDatasetsBlock` IIFE.
