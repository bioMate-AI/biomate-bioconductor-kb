# Research-Agent v2 — Real-backend SSE smoke (dev EC2)

Date: 2026-05-19
Target: `https://dev-public.biomate.ai` (52.42.49.175)

## Result: ✓ PASS — 8/8 events round-trip cleanly

The sandbox's `?live=real` mode contract is **proven end-to-end** against
the actual dev EC2 SSE pipeline. The browser-UI smoke (sandbox served
from dev origin) is a separate follow-up; this run verifies the wire
contract independently.

## What was tested

```
real_sse_smoke.cjs — node
    ↓ openSSE(GET /api/workflows/<smoke-inv>/events)
        ↓ EventSource handshake (HTTP 200, Content-Type: text/event-stream)
        ↓ receives "event: connected" frame
    ↓ for each of 8 representative chat_progress events:
        POST /internal/sse-inject {invocation_id, event_type, data}
            → WorkflowSSEManager.injectRawEvent
            → write "event: chat_progress\ndata: {…}\n\n" to all listeners
        ↑ SSE listener receives raw text, parses JSON, runs through
          translateBiomateEvent + deriveSpeakerFallback
    ↓ assert: each event arrived; speaker derived correctly per prefix;
              plan.shown items survived; friendly_message preserved
```

8 events injected — covered every speaker prefix:

| kind                            | expected speaker | result |
|---------------------------------|------------------|--------|
| `workflow.submitted`            | `wf`             | ✓      |
| `plan.shown`                    | `plan`           | ✓ (planShow with 1 item) |
| `workflow.phase_started`        | `wf`             | ✓      |
| `workflow.qc_gate_warning`      | `qc`             | ✓      |
| `workflow.autoloop_started`     | `loop`           | ✓      |
| `deepagent.start`               | `agent`          | ✓      |
| `findings.generated`            | `find`           | ✓      |
| `workflow.completed`            | `wf`             | ✓      |

## What this confirms

1. The dev EC2 frontend (nginx + node express) **accepts and routes
   `/internal/sse-inject` POSTs** to `WorkflowSSEManager.injectRawEvent`.
2. `GET /api/workflows/:inv/events` **streams SSE frames with the
   correct `text/event-stream` content type** and the `chat_progress`
   event type the sandbox subscribes to.
3. The wire payload from a narrator-style emit (or our injected
   substitute) **matches the shape `translateBiomateEvent` expects** —
   `{ kind, invocation_id, friendly_message, ts, technical }`. No
   `speaker` on the wire; client-side `deriveSpeakerFallback(kind)`
   correctly produces all six speaker pills.
4. The `plan.shown` event's `technical.items` array **survives**
   inject → SSE → JSON.parse → translation, ready to drive the
   PlanChecklist.

## What's still open

- **Browser UI smoke**: sandbox HTML loaded from dev origin so that
  EventSource cross-origin + credentials behaves like production. Two
  options:
  1. Upload `frontend/research_agent_v2/` to dev via `sync_to_dev.sh`
     and serve from `https://dev-public.biomate.ai/_/research-agent-v2/`.
  2. Run a local sandbox + a small same-origin proxy to dev.

- **Live workflow events** (not injected): for the running ADMET
  (`2545a979…`) and CryoSPARC (`b73b56f2…`) invocations on dev right
  now, the SSE stream connected but no `chat_progress` events fired
  during a 22-second observation window. Two possible reasons —
  invocations were mid-phase (long compute, no narrator calls between
  events), or the running workflows pre-date the
  `workflow_chat_narrator` wiring on their job runners. Worth a
  follow-up: start a fresh small ADMET smoke run and observe the
  event stream end-to-end for narrator emits.

## How to re-run

```bash
cd frontend/research_agent_v2
node real_sse_smoke.cjs                          # defaults to dev
node real_sse_smoke.cjs http://localhost:5000    # local frontend
```

Exits 0 on success, prints failure list and exits 1 on any mismatch.
Self-contained (no playwright, no browser, no auth) — safe to drop
into CI as a wire-contract regression check.
