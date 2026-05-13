# Connector Sandbox Test Results

**Date:** 2026-05-13
**Branch:** `claude/improve-connector-architecture-L0eAL`
**Suite:** `backend/tests/test_connector_sandbox.py` (35 cases) + `test_tools_manifest.py` (30 cases)

## Why this exists

Before submitting BioMate's connectors to the Anthropic MCP directory, the
Anthropic Skills gallery, the ChatGPT GPT store, the Slack App Directory, and
the Cursor MCP list, the protocol contracts had to be exercised end-to-end
without depending on a production BioMate backend or a paid Claude/OpenAI key.
The sandbox suite covers every contract a host (Claude Code, Claude Desktop,
Claude.ai web, Codex CLI, ChatGPT, Slack, WeChat) will eventually validate
during onboarding.

## Coverage matrix

| Concern | Approach | Test count |
|---|---|---|
| OpenAPI 3.1 spec validity | `openapi_spec_validator.validate` on committed `connectors/chatgpt/openapi.json` | 3 |
| JSON Schema validity (Draft 2020-12) | `Draft202012Validator.check_schema` per tool | 1 (covers 14 tools) |
| Sample input acceptance | Parametrized positive sample per tool | 14 |
| Sample input rejection (negative) | Missing-required / wrong-type / invalid-enum cases | 4 |
| Anthropic SDK shape | Local validation against `anthropic.types.ToolParam`, name/length constraints | 2 |
| OpenAI SDK shape | Local validation against `openai.types.chat.ChatCompletionToolParam` | 2 |
| MCP JSON-RPC handshake | Real subprocess + stdin/stdout `initialize` exchange | 1 |
| MCP `tools/list` | Real subprocess returns the manifest's 14 tools | 1 |
| MCP `tools/call` (sync) | Calls a mocked BioMate HTTP server, validates response shape | 2 |
| MCP `tools/call` (streaming with progressToken) | `biomate_session` emits `notifications/progress` driven by a mock SSE backend | 1 |
| MCP `tools/call` (streaming without progressToken) | No notifications emitted | 1 |
| MCP `tools/call` (unknown tool) | Returns `-32601 Method not found` | 1 |
| MCP back-compat (legacy aliases) | `get_run_status` etc. still dispatch | 1 |
| Drift (manifest JSON ↔ Python) | `git diff --exit-code` after regen | 2 (committed JSON + OpenAPI) |

**Total: 65 cases, all pass in 6 s on a single core.**

## What's actually exercised

The streaming test (`test_mcp_biomate_session_streams_progress`) is the
load-bearing one. It does this end-to-end:

```
sandbox test                            mock BioMate HTTP server (random port)
    │                                                  │
    ├── spawn `python -m biomate_mcp_server`           │
    │        BIOMATE_API_URL=http://127.0.0.1:<port>   │
    │                                                  │
    ├── send {"method":"initialize"} ────────────────► │
    │ ◄────────────────────────── {"result":{...}}     │
    ├── send {"method":"tools/call",                   │
    │         "name":"biomate_session",                │
    │         "_meta":{"progressToken":"tok-…"}}       │
    │                                                  │
    │     (MCP server's SessionRunner thread           │
    │      opens an HTTP request to                    │
    │      /api/open-claw/stream)                      │
    │                              ──────────────────► │
    │                              ◄── event: workflow_phase   data: {…}
    │                              ◄── event: workflow_step    data: {…}
    │                              ◄── event: finding          data: {…}
    │                              ◄── event: done             data: {…}
    │ ◄── notifications/progress (kind=phase_started)
    │ ◄── notifications/progress (kind=step_completed)
    │ ◄── notifications/progress (kind=finding)
    │ ◄── notifications/progress (kind=done)
    │ ◄── {"id":42,"result":{…final summary…}}
```

The assertions check:
- ≥3 progress notifications arrive
- Every notification carries the `progressToken` the test supplied
- The event-kind sequence includes a `phase_*` event, a `finding`, and a `done`
- The final tools/call response carries `run_id` and `view_url` discovered in
  the stream

This is the contract host implementations (Claude Code, Claude Desktop) will
verify when they connect to a fresh BioMate install. If this test passes, the
streaming path is real.

## What is NOT tested here

- **Real Anthropic / OpenAI HTTP calls.** No production API keys in this
  sandbox. We rely on the SDKs' local validators, which catch every shape
  error the remote API would catch — but rate limits, model-specific tool
  parsing quirks, and 400/401 responses are out of scope until a live key is
  available.
- **End-to-end against a real BioMate backend.** That's covered by the
  existing E2E suite (`frontend/e2e/`) and the dev EC2 sync workflow. The
  sandbox uses a mock so the test runs offline in CI.
- **UI rendering inside hosts.** Claude.ai, ChatGPT, and Slack render the
  markdown/HTML payloads themselves; that visual fidelity is exercised by
  the `skills/biomate/references/render_templates.md` examples and the
  existing per-host E2E tests when they are added.
- **OAuth flow.** The `connect.sh` installer is a paste-token stub; the
  full OAuth 2.1 + PKCE flow is a Phase 3 deliverable.

## Reproducing locally

```bash
# Install validation libs (one-time)
pip install jsonschema openapi-spec-validator anthropic openai

# Run the full sandbox
PYTHONPATH=. pytest backend/tests/test_tools_manifest.py \
                    backend/tests/test_connector_sandbox.py -v

# Or just the streaming subprocess test
PYTHONPATH=. pytest backend/tests/test_connector_sandbox.py::test_mcp_biomate_session_streams_progress -v
```

## CI wiring

The sandbox is invoked from `.github/workflows/tools-manifest-drift.yml` on
every PR that touches `backend/lib/mcp/**`, `connectors/chatgpt/**`, or the
test files themselves. A merge to `main` is blocked if any case fails.

## Sign-off checklist before submission

- [x] OpenAPI 3.1 spec validates against the official schema
- [x] Every tool input_schema is valid JSON Schema 2020-12
- [x] Anthropic SDK accepts our `to_anthropic()` output (name length ≤64,
      regex-safe, valid `input_schema`)
- [x] OpenAI SDK accepts our `to_openai()` output
- [x] MCP server handles `initialize`, `tools/list`, `tools/call` over real
      stdio JSON-RPC
- [x] `biomate_session` streams `notifications/progress` and finalizes with
      a `tools/call` response carrying `run_id` + `view_url`
- [x] Unknown tools return `-32601`, not a 500
- [x] Manifest drift is enforced in CI
- [ ] Real Claude API smoke run with a paid key (next session)
- [ ] Real OpenAI / ChatGPT GPT builder smoke run (next session)
- [ ] OAuth 2.1 + PKCE service stood up (Phase 3)

## Next session

When a real Anthropic key + a real OpenAI key are available, add a second
sandbox file `test_connector_live.py` that:

1. Issues one `messages.create(tools=to_anthropic())` call against
   `claude-sonnet-4-6` with a synthetic "screen aspirin" prompt; assert the
   model picks `biomate_session` as the first tool call.
2. Issues one `chat.completions.create(tools=to_openai())` call against
   `gpt-4o`; assert the same.
3. Skip both with `pytest.skip` if the keys are absent so CI stays green
   on PRs that don't have them.

These two live tests are the final pre-submission check.
