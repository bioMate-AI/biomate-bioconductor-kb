# Research-Agent v2 — backend↔frontend SSE event contract

Date: 2026-05-19
Purpose: pin down what the sandbox needs from the real backend so the
`?live=real&inv=<id>` smoke against dev EC2 either works on the first
try or fails for a documented reason.

## Wire path

```
qc_trace_monitor.py / nextflow_executor.py
    │  _narrator_emit(invocation_id, kind, technical, sse_callback=…)
    ▼
workflow_chat_narrator.emit()
    │  builds { kind, invocation_id, friendly_message, ts, technical }
    │  logs [WORKFLOW]…
    │  sse_callback("chat_progress", payload)
    ▼
nextflow_monitor.py: sse_callback() POSTs to <frontend>/internal/sse-inject
    ▼
frontend/server/routes.ts: app.post("/internal/sse-inject")
    │  sseManager.injectRawEvent(invocation_id, "chat_progress", data)
    ▼
WorkflowSSEManager.injectRawEvent — writes to every connected client:
    event: chat_progress
    data: { …payload… }
    ▼
Browser EventSource @ GET /api/workflows/:invocationId/events
    │  routes.ts → sseManager.handleConnectionByInvocationId
    ▼
sse-adapter.js: connectRealBiomateStream(inv).start(onEvent)
    │  es.addEventListener("chat_progress", msg => onEvent(JSON.parse(msg.data)))
    ▼
ResearchApp.translateBiomateEvent(ev)
    │  → planShow / chatLine / showCard / await / startCountdown
    ▼
ResearchApp.applyEvent — engine state updates → React rerender
```

## Event payload — backend emits

```json
{
  "kind":             "workflow.phase_started",
  "invocation_id":    "inv-12345",
  "friendly_message": "Step 2/5: STAR alignment…",
  "ts":               1747700000.123,
  "technical":        { "phase_name": "STAR alignment", "n": 2, "of": 5 }
}
```

Fields **never** sent by backend (must be derived client-side):
- `speaker` — derived in `deriveSpeakerFallback(kind)` from the kind prefix
  (mirror of the backend's `derive_speaker` Python helper).
- `__planUpdate` / `__showCard` / `__await` — these are mock-only
  shaping events; real-mode does not emit them.

## What real-mode already works for

Confirmed call sites in the backend that emit through
`workflow_chat_narrator.emit()`:

| kind                          | source                          |
|-------------------------------|---------------------------------|
| `workflow.qc_gate_warning`    | qc_trace_monitor.py:5552, 5751  |
| `workflow.qc_gate_blocked`    | qc_trace_monitor.py:5552 branch |
| (any kind callers pass in)    | nextflow_executor.py:88         |

Frontend translator handles **every** `workflow.*` / `findings.*` /
`deepagent.*` / `plan.*` kind via the generic `chatLine` default
branch with speaker derived from the prefix. Anything new just renders
as a chat line — no code change needed unless we want a card.

## What real-mode does NOT yet have

These mock-only kinds drive cards / decision UI in the sandbox; without
them, real-mode shows the chat thread but no:

| missing event   | drives                                |
|-----------------|---------------------------------------|
| `plan.shown`    | PlanChecklist initial render          |
| `__planUpdate`  | per-item status (running/done/warn)   |
| `__showCard`    | PilotPrompt / Promotion / Comparison / Findings cards |
| `__await`       | engine "awaiting" gate for decisions  |
| `__startCountdown` | 10-s auto-proceed timer            |

To make real-mode render the same UX as the mock, the backend must
either (a) emit `plan.*` and structured `findings.*` events through the
narrator, with the same `technical` shape the mock uses, or (b) the
research-agent UI must fetch plan + cards via separate endpoints
(`/api/research/plan`, `/api/research/rationale/:phase_id`, etc.)
keyed by `invocation_id`.

Recommendation: extend the narrator with three additional kinds and
shapes, all backed by `technical` so the frontend translator picks
them up via the same `chatLine` → `showCard` mapping path:

| kind                         | technical                                    |
|------------------------------|----------------------------------------------|
| `plan.shown`                 | `{ items: [{id,title,status,est_s}, …] }`    |
| `plan.item_updated`          | `{ id, status, meta? }`                      |
| `findings.generated`         | `{ title, runtime, samples, rows: [[k,v],…] }` (renders FindingsChatCard) |

Comparison + pilot-promotion cards are out-of-scope until the auto-loop
backend can compute Run A vs Run B diffs and emit them through the
narrator. Until then, real-mode shows the chat thread plus findings;
cards stay mock-only.

## Smoke-test command (when dev has a live invocation)

```bash
# On dev EC2 — confirm chat_progress events flowing for an active run:
curl -sN http://localhost:5000/api/workflows/<INV>/events | head -50

# From a workstation — point the sandbox at dev:
cd frontend/research_agent_v2 && python3 -m http.server 8765 &
open 'http://127.0.0.1:8765/index.html?live=real&inv=<INV>'
# (set Origin so cookies/auth pass — or run from same origin as dev frontend)
```

Expected:
- chat-thread populates as Nextflow phases complete (workflow.phase_*,
  workflow.qc_*), each line with the right speaker pill from
  `deriveSpeakerFallback`.
- plan checklist + cards stay empty (gap documented above).
- 0 JS errors.
