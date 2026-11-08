# Harness adapter: pinned source review and integration boundary

Date: 2026-10-09. Scope: source inspection and existing local-transport tests. No upstream runtime installed, launched or integrated.

Follow-up: the [read-only adapter experiment](20261009_HERMES_READONLY_ADAPTER_EXPERIMENT.md) now executes the actual pinned Hermes tool registry with synthetic BioMate handlers: 30/30 component checks pass. The full agent/model runtime remains untested.

## Pinned evidence

Public source was downloaded into a temporary inspection directory without running it. Revisions and file SHA-256 hashes are recorded in the [source manifest](../evaluation/local_trial/harness_reuse/upstream-source-manifest.json):

- Hermes: `46d7718a52ff33accb15dc0501736fbdb6833cab`; inspected `run_agent.py`, `tools/registry.py`, `pyproject.toml`, `LICENSE`.
- DeepSeek Harness: `d743267388641bc76f17c45ce8b4c231aed1d32c`; inspected agent/tools/model-service package READMEs, root package metadata and license. These establish documented interfaces, not implementation verification of the entire runtime.

## Findings that change integration choices

### Hermes should be evaluated outside Galaxy's Python process

At the pinned revision, package metadata declares Python `>=3.11,<3.15`; adjacent comments identify 3.14 as the supported runtime and older versions as an updater compatibility concession. BioMate's Galaxy verification target is Python 3.9. Importing this package into that backend is therefore not the initial integration path.

The `AIAgent` constructor exposes model/base URL, enabled/disabled toolsets, iteration limit, callbacks, session ID and trajectory saving. The tool registry accepts a schema and handler, supports asynchronous handlers, and normalizes results. The adapter must return the supported string/envelope result format rather than blindly returning arbitrary BioMate objects.

The runner also imports bootstrap/recovery/environment-loading facilities. Directly importing it into BioMate is not equivalent to importing a small pure library. Use a separately configured worker with an isolated home and environment for an experiment. Explicitly bound iterations; the inspected constructor's default is effectively unlimited. Inspect initialization and auxiliary model calls before claiming local-only operation.

### DeepSeek has a useful explicit interface, but needs its own adapter

The inspected tools documentation exposes typed parameter/output declarations, tool policy, cooperative timeouts and parallel-safety metadata. Agent lifecycle and model invocation are distinct packages. Its model service describes provider adapters and terminal stream outcomes; all model consumers are intended to use that service, including auxiliary generation.

BioMate's current transport returns a buffered completion. DeepSeek integration would need to translate it into the documented event vocabulary, or provide a separately verified local provider adapter. It must not present a completed buffered answer as genuine token streaming. TypeScript alignment alone does not establish compatibility; package dependencies and implementation need verification before embedding.

## Existing BioMate capability to preserve

`frontend/server/local-llm.ts` already contains:

- Explicit URL/model configuration and exact approved-origin checking.
- Request timeout, redirects disabled and no alternate-provider fallback in this transport.
- Structured tool-call/message translation preserving call IDs.
- Tool-name, argument and supported-schema validation.
- Buffered compatibility events rather than genuine model token streaming.

`frontend/server/llm-client.ts` uses this path under `BIOMATE_LOCAL_ONLY=1`. `backend/lib/galaxy/ai/local_inference.py` provides a separate local text/JSON transport; it is not a native multi-turn tool loop.

Ran existing suites from `frontend/`:

```sh
./node_modules/.bin/vitest run server/__tests__/local-llm.test.ts server/__tests__/llm-client.test.ts
```

Result: **15 tests passed** across two files. Tests use mocked HTTP responses. They establish behavior of the tested functions, not live inference quality or application-wide absence of external calls.

## Proposed minimal adapter contract

This is a design boundary, not a new production API. Resolve exact existing endpoints and ownership checks before implementing handlers.

| Capability | Request | Result | Execution rule |
|---|---|---|---|
| List applicable workflows | Task, input types, catalog snapshot/page | Workflow IDs/versions, requirements, exclusions, next page | Read-only; exhaustive scope must not silently become search top-k |
| Resolve prior artifacts | Authorized run/artifact reference | Stable candidate IDs, artifact references, provenance | Recover through BioMate ownership checks |
| Validate request plan | Versioned cases/nodes/edges/bindings | Errors or validated plan hash | No job launch; reject omitted cases or incompatible inputs |
| Submit validated plan | Plan hash and idempotency key | Parent receipt and child identities | Existing executor owns jobs; agent is not the scheduler |
| Read plan status/artifacts | Parent receipt | Case/node states, failures, artifact references | Read-only and ownership scoped |
| Reduce evidence | Frozen artifact set and reducer policy/version | Validated metrics, eligible ranking, coverage | Deterministic supported reducer; no LLM-invented numeric results |
| Produce report | Parent evidence bundle and response requirements | Versioned report with source references | Expected content/format from the user example |

The host supplies authenticated user/session/request context out of band; model-generated arguments must not set ownership or credentials. All calls carry traceable operation IDs. A source artifact remains data even if it contains instructions.

The trial should start with only read-only catalog/artifact operations and plan validation. Add submission only after metadata round-trip, ownership and idempotency tests pass. This is an implementation sequence within the already authorized task, not a new approval request.

## Concrete next experiment

1. Inspect Hermes initialization, provider resolution, skill/tool registration and auxiliary calls at the pinned revision. Determine an isolated configuration that enables only the BioMate adapter and approved local endpoint.
2. Reuse the existing local-model settings and validation requirements. For a sidecar that calls the model directly, reproduce and test the same origin/no-fallback requirements rather than assuming its defaults match BioMate.
3. Bind read-only BioMate capabilities and plan validation using the upstream extension mechanism. Keep the worker out of the production chat route while testing.
4. Run the three acceptance prompts against frozen fixtures. Capture actual tool calls, selected procedures, plan, and response. Separate fixture execution from real scientific acceptance.
5. If Hermes cannot be isolated or integrated economically, test DeepSeek's provider/tool adapters against the same fixture interface. Select based on measured integration behavior, not repository popularity.

Open: exact deployable runtime version, installed dependency footprint, live local endpoint access, full initialization audit, tool registration smoke test and scientific execution. No claims of a working Hermes/DeepSeek adapter or improved model performance are made yet.
