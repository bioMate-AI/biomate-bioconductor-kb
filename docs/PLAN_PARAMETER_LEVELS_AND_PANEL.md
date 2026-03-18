# Plan: Parameter Levels + Right Artifact Panel

**Date**: 2026-03-12
**Status**: In Progress
**Branch**: connection_formal

---

## Overview

Two parallel workstreams:
- **A** (high priority): Proper parameter level system (required / recommended / optional / advanced)
- **B** (low priority): Move workflow viewer into a right-side artifact panel (like Claude.ai)

---

## Workstream A: Parameter Level System

### Problem

The AI tool DB stores rich parameter metadata per tool:
```json
{
  "name": "k_mer_length",
  "label": "K-mer length (in bp)",
  "type": "integer",
  "help": "The length of a k-mer",
  "optional": false
}
```

But this metadata is **never forwarded to the frontend**. The viewer:
- Infers type from runtime value (fragile)
- Hardcodes `required: false` for every param
- Shows no help text
- Shows no default vs. current distinction
- Shows no AI-suggested values in context

### Four Parameter Levels

| Level | Criteria | UI Treatment |
|---|---|---|
| `required` | `optional: false` in DB, no default value | Red asterisk `★`, input highlighted, **blocks Run** if empty |
| `recommended` | Key appears in `scientific_rationale.parameter_hints` | Purple highlight, pre-filled with AI suggestion, shows rationale tooltip |
| `optional` | `optional: true`, has a default value | Normal appearance, shows default value greyed |
| `advanced` | `optional: true` AND name contains `debug`, `advanced`, `cache`, `temp`, `verbose`, `log`, `seed` | Hidden behind "Show advanced" toggle |

### Schema: `parameter_metadata` (backend → frontend)

The backend must include this field in every workflow response:

```json
{
  "parameter_metadata": {
    "input_fastq": {
      "label": "Input FASTQ",
      "type": "data",
      "help": "Input reads in FASTQ format",
      "optional": false,
      "default": null
    },
    "threads": {
      "label": "Threads",
      "type": "integer",
      "help": "Number of CPU threads to use",
      "optional": true,
      "default": 4
    },
    "min_quality": {
      "label": "Minimum base quality",
      "type": "integer",
      "help": "Trim bases below this Phred quality score",
      "optional": true,
      "default": 20
    }
  }
}
```

**Type values** (from Galaxy tool format): `text`, `integer`, `float`, `boolean`, `data`, `select`, `file`

### Level Derivation (frontend)

```typescript
function deriveParamLevel(
  key: string,
  meta: { optional: boolean; default: any } | undefined,
  rationaleHints: string[]  // param names that appear in parameter_hints
): 'required' | 'recommended' | 'optional' | 'advanced' {
  if (rationaleHints.includes(key)) return 'recommended';
  if (!meta) return 'optional';  // no metadata = treat as optional
  if (!meta.optional && (meta.default === null || meta.default === undefined)) return 'required';
  const advancedKeywords = ['debug', 'advanced', 'cache', 'temp', 'verbose', 'log', 'seed', 'tmp'];
  if (advancedKeywords.some(kw => key.toLowerCase().includes(kw))) return 'advanced';
  return 'optional';
}
```

### ParameterGroup Sections Layout

```
┌─ Required Parameters ───────────────────────────────────────┐
│ ★ Input FASTQ     [               ] upload                   │
│ ★ Reference genome [ hg38    ▼ ]                             │
└─────────────────────────────────────────────────────────────┘

┌─ Recommended ───────────────────────────────────────────────┐
│ ○ Threads          [ 8  ]  ✦ AI suggests 8 (for efficiency) │
│ ○ Min quality      [ 20 ]  ✦ for paired-end reads           │
└─────────────────────────────────────────────────────────────┘

▶ Optional (12 parameters — click to expand)

▶ Advanced (hidden)
```

### Run Button Validation

- "Run Workflow" / "Confirm & Run" is **disabled** when any `required`-level param has an empty value
- Show inline validation message: "Fill required parameters before running"

### Files Modified

| File | Change |
|---|---|
| `backend/lib/galaxy/ai/ai_assistant.py` | Build `parameter_metadata` dict from tool DB and include in workflow output |
| `frontend/client/src/components/nextflow-workflow-viewer.tsx` | Extend `ViewerParameter` with `level` + `help`, update `buildViewerParameters()` to use metadata |
| `frontend/client/src/components/parameter-group.tsx` | Group params by level, add visual sections, required validation |
| `frontend/client/src/components/phase-card.tsx` | Per-step params also respect level grouping |

---

## Workstream B: Right Artifact Panel

### Problem

Workflow viewer is embedded inline in the chat bubble. This:
- Makes the chat very long/scrolled when a workflow is shown
- Makes it hard to chat while viewing the workflow
- Doesn't match modern AI assistant UX (Claude.ai, Cursor, etc.)

### Target Layout

```
┌────────────────────┬─────────────────────────────────────────┐
│  Chat (340px)      │  Artifact Panel (flex-1)                 │
│  ─────────────── │  ┌─ RNA-seq: Diff. Expression ──────────┐ │
│  [user message]    │  │  AWAITING REVIEW                    │ │
│  [AI response]     │  │                                     │ │
│  [→ Workflow card] │  │  Tabs: Steps | Execution | Results  │ │
│  [user message]    │  │  ─────────────────────────────────  │ │
│                    │  │  1. Quality Control        [Pending] │ │
│                    │  │     Parameters: (3)        ▶        │ │
│                    │  │  2. Read Alignment          [Pending]│ │
│                    │  │     Parameters: (2)        ▶        │ │
│  ─────────────── │  └────────────────────────────────────┘ │
│  [ type a message ]│                                         │
└────────────────────┴─────────────────────────────────────────┘
```

### Key Changes

**`chat-with-artifacts.tsx`**:
- Outer layout: `flex flex-row h-full`
- Left pane: `w-[360px] flex-shrink-0 border-r flex flex-col` (chat + input)
- Right pane: `flex-1 overflow-auto` (only shown when `activeArtifactMessageId !== null`)
- State: `activeArtifactMessageId: string | null`
- Auto-set when a new workflow message arrives (last workflow message in history)
- Expose `setActiveArtifactMessageId` so chat messages can open panel

**`workflow-artifact.tsx`**:
- Add `panelMode?: boolean` prop
- In panel mode: no outer Card wrapper, full height, inner tabs for Steps/Execution/Results
- In inline mode (current): compact card with "Open in panel →" button to avoid full viewer inline

**`chat-message.tsx`**:
- When a message has a workflow artifact AND panel mode is active: render compact pill instead of full viewer
- Compact pill: `[Workflow name] [Status badge] [Open →]`

### Files Modified

| File | Change |
|---|---|
| `frontend/client/src/components/chat-with-artifacts.tsx` | Add split-pane layout, `activeArtifactMessageId` state |
| `frontend/client/src/components/workflow-artifact.tsx` | Add `panelMode` prop, compact inline mode |
| `frontend/client/src/components/chat-message.tsx` | Compact workflow pill when panel active |

---

## Agent Assignment

| Agent | Workstream | Files | Dependencies |
|---|---|---|---|
| Agent 1 | A — Backend metadata | `ai_assistant.py` | None |
| Agent 2 | A — Frontend levels | `parameter-group.tsx`, `nextflow-workflow-viewer.tsx` | Needs schema from above |
| Agent 3 | B — Right panel | `chat-with-artifacts.tsx`, `workflow-artifact.tsx`, `chat-message.tsx` | None |
