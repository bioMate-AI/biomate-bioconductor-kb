# How My Proposal Relates to the Existing WorkflowHistoryDialog

**Date:** 2026-06-01
**Branch:** `integration/next-phase`
**Trigger:** User reminder that we already added a Recent Runs sidebar feature with search + reuse.

## What's already there (you're right, this exists)

**Sidebar → "Workflows" button** opens `WorkflowHistoryDialog`
(`frontend/client/src/components/workflow-history-dialog.tsx`, 9.8 KB,
shipped via Gap 4 — `docs/20260521_GAP4_SIDEBAR_RUN_HISTORY.md`).

Two tabs:

| Tab | What it shows |
|---|---|
| **Recent runs** | Last 50 server-side runs scoped to the user (`scope=all_chats`), via `GET /api/workflows/runs/overview`. Each row = status dot, workflow name, status text, time-ago, and two buttons: **Open** (jumps to the chat session that ran it) and **Run again** (re-fires with prior params pre-filled via `useRunAgainParamCarryover`). |
| **Starred** | Pinned-favorites tab (localStorage-only). |

Backed by the persistent layer:
- `execution_runs` Postgres table (253+ rows verified earlier)
- `runs-outputs-service` for output recovery
- `useRunAgainParamCarryover` hook (Gap 3) for param carry-forward
- Activity dot in `app-sidebar.tsx` per-chat for at-a-glance state

This is a **complete UI** for run discovery + re-execution by a human.

## What I proposed (Galaxy History tools for the chat agent)

`docs/20260601_GALAXY_HISTORY_THE_REAL_GAP.md` proposed 3 agent tools:
- `list_history(after?, limit?)` — agent reads the user's Galaxy history datasets
- `read_history_dataset(hda_id, lines?)` — agent reads a single HDA's content
- `find_history_dataset(name_pattern, format?)` — agent maps natural language → hda_id
- Plus `_buildHistoryContextBlock()` for prompt injection

This is **complete tool access** for the LLM agent to USE past data inside its reasoning.

## Why these are complementary, not duplicate

The two pieces address **different users**:

| Layer | Audience | Question it answers |
|---|---|---|
| `WorkflowHistoryDialog` (existing) | **Human** browsing the UI | "What runs did I do? Let me open one or re-fire it." |
| Galaxy History agent tools (proposed) | **LLM agent** during chat | "What were the IC50 values from that cyp_ddi run? Let me read them and answer the user's question." |

The dialog gets the user TO a past run. The agent tools let the agent USE the past run's outputs without the user re-uploading anything.

### Concrete scenario where existing UI doesn't help

User opens the **Workflows → Recent runs** dialog, sees their `cyp_ddi_panel` run from yesterday, **clicks "Open"** → lands in the chat session that produced it → asks in chat:

> *"What was the CYP3A4 IC50 for that aspirin compound?"*

Current behavior (tested earlier this turn):
- Agent runs `find $DATA_DIR` → empty
- Agent runs `query_domain_knowledge` → generic answer
- Agent responds: *"please upload your output file"*

The user is **literally inside the right chat session**, looking at the workflow panel with the result, but the agent can't read the result file. The dialog got them to the room; the agent has no key.

### How the proposal closes the gap

After the 3 agent tools ship:

> *"What was the CYP3A4 IC50 for that aspirin compound?"*

- Agent calls `find_history_dataset(name_pattern="cyp.*ic50", format="json")` → returns `hda_id=abc123, name="cyp_inhibition_results.json"`
- Agent calls `read_history_dataset(hda_id="abc123")` → returns the JSON contents
- Agent: *"CYP3A4 IC50 was 24.8 µM (non-inhibitor classification)."*

## Where the integration goes in the UI

Two options, ranked by simplicity:

### Option A (recommended) — invisible to the UI, surfaces in chat answers

No UI changes. Just add the agent tools server-side. When the user is in any chat session, the agent automatically has visibility into the session's Galaxy history + history-context block. User feels it as "the chat suddenly knows about my previous runs." Zero new sidebar items, zero new dialogs.

This is the cheapest deployment path and matches the user mental model (chat = conversation with memory).

### Option B — visible UI hint

Add a small status indicator inside the chat input or above the message list:

```
[ History context active: 5 datasets, 3 recent runs available  ⓘ ]
```

with a tooltip listing the available datasets. Click expands to a mini-list with `@reference` shortcuts ("Insert @cyp_ddi_results"). Same backend, but discoverability is explicit.

Option B is nicer UX but +1-2 days of frontend work. Option A is shippable in a single backend session.

## The relationship in one diagram

```
┌────────────────────────────────────────────────────────────────┐
│ Sidebar > Workflows > "Recent runs" (existing)                 │
│ — Human navigation. Open / Run again.                          │
└────────────────────────────────────────────────────────────────┘
                              │
                              │ user clicks Open
                              ▼
┌────────────────────────────────────────────────────────────────┐
│ Chat session (existing UI)                                     │
│ ─ Workflow panel with run result visible                       │
│ ─ Chat input below                                             │
│                                                                │
│   User: "What was the CYP3A4 IC50?"                           │
│                                                                │
│   ┌────────────────────────────────────────────────────┐      │
│   │ Chat agent (the gap is here)                       │      │
│   │ Tools today: run_code, read_file, query_knowledge  │      │
│   │ Tools needed: list_history, read_history_dataset,  │      │
│   │               find_history_dataset                 │      │
│   └────────────────────────────────────────────────────┘      │
│                              │                                 │
│                              ▼ with new tools:                 │
│   Agent: "CYP3A4 IC50 was 24.8 µM (non-inhibitor)."           │
└────────────────────────────────────────────────────────────────┘
```

The existing dialog handles "find a past run." The proposed tools handle "answer a question about a past run's contents." Both rely on the same Galaxy History persistence layer.

## Summary

- **Existing sidebar UI**: works as designed — human-facing run discovery + re-execution.
- **Proposed agent tools**: extend the SAME Galaxy History to the LLM agent for in-chat output reading.
- **Recommended integration**: Option A — no UI change, ship the tools + history context block. The dialog stays as-is; chat just gets smarter.
- **Effort**: ~125 lines backend, no UI changes for v1. ~2-3 hours including tests.

## Backward compatibility / risk

- Existing dialog and Gap 3 (param carryover) untouched
- New tools are additive — the agent simply has more options
- The history-context prompt block adds ~10-20 datasets × short metadata per chat turn (~500 tokens at most) — minimal cost, doesn't break existing prompts
- The user sees no UI regression; only the agent becomes more useful
