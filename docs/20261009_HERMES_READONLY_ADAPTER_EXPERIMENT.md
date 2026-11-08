# Hermes read-only BioMate adapter experiment

Date: 2026-10-09. **30/30 component integration checks pass. No LLM or scientific job ran.**

Follow-up: [real-model OpenRouter evaluation](20261009_OPENROUTER_HARNESS_EVALUATION.md) now exercises model-generated calls through this registry and adapter. Its results and limitations are separate from the component-only checks below.

## What is implemented

The [fixture adapter](../evaluation/local_trial/harness_reuse/fixture_adapter.py) registers three tools with the actual Hermes `ToolRegistry`:

- `biomate_read_context`: returns the host-bound case, synthetic inputs and expected coverage.
- `biomate_list_workflows`: returns the complete fixture catalog with an explicit end-of-pagination marker.
- `biomate_validate_plan`: checks catalog membership, stable step keys, graph validity and frozen case coverage.

The handlers return the JSON-string format supported by Hermes. They reuse the structural validators in BioMate's **provisional** `backend/lib/galaxy/chain/dag.py`; that is not approval of the earlier scheduler patch. All fixtures are synthetic, including tool names, paths and candidate IDs. No chemical predictions or real shortlisted sequences are manufactured.

Three cases are bound separately: comparison of three methods, six inhibitor–target pairs, and six synthetic candidates evaluated by two synthetic property methods. The peptide fixture exercises 12 candidate/method cases; it does not pretend to reproduce the external platform's 16 sequences or actual predictors. Its ranking and report remain outside this component test.

## Actual upstream reuse

The [smoke runner](../evaluation/local_trial/harness_reuse/smoke_hermes_registry.py) imports unmodified Hermes registry code at revision `46d7718a52ff33accb15dc0501736fbdb6833cab`. It verifies hashes of the registry, its package initializer and constants module against the [source manifest](../evaluation/local_trial/harness_reuse/upstream-source-manifest.json) before importing them.

This tests registration and dispatch with real upstream code, not a mock registry. The full `AIAgent` runtime and provider stack are not installed. An audit hook rejects socket connections, DNS resolution and subprocess creation during the registry test; this is a test assertion mechanism, not a production security sandbox.

Run from the repository root with the pinned files present:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 evaluation/local_trial/harness_reuse/smoke_hermes_registry.py --hermes-source /tmp/biomate-harness-review/hermes-agent
```

The temporary source location is not a deployment dependency. The manifest contains exact public download URLs and checksums needed to reproduce the source inspection. Upstream code was not copied into the product or installed into Galaxy.

## Results

[Captured results](20261009_HERMES_REGISTRY_SMOKE.json): 30 passed, zero failed, ten checks per case:

1. Only the three read-only tools are registered.
2. Context is bound to the selected case.
3. Catalog exhaustion is explicit.
4. A complete plan validates without authorizing execution.
5. Removing an expected case is rejected.
6. An unavailable workflow is rejected.
7. A dependency cycle is rejected.
8. Model-supplied coverage overrides are rejected.
9. Attempts to switch context through tool arguments are rejected.
10. Job submission is unavailable.

Plans are supplied by the test runner. This result does not measure an LLM's ability to choose tools, construct plans or produce the expected report. It also does not repair the nine existing product-boundary failures.

## Remaining integration work

- Configure a complete isolated Hermes worker and inspect initialization/auxiliary model calls. Current source offers memory/context/review controls, but their full behavior is not yet verified. Do not claim that one constructor flag guarantees no external traffic.
- Connect an approved local endpoint. The current shell lacks the full `BIOMATE_LOCAL_LLM_URL`, `BIOMATE_LOCAL_LLM_MODEL` and `BIOMATE_LOCAL_LLM_ORIGIN` configuration. This is an environment observation, not a claim that no server exists elsewhere. No endpoint was guessed or replacement compute launched.
- Replace synthetic catalog/artifact handlers with authenticated BioMate read-only adapters after identifying the actual API contracts. The test's host-bound context is not a substitute for production ownership enforcement.
- Run actual model conversations for the three cases with the same catalog/evidence and report requirements. Record generated plans and tool traces separately from deterministic fixtures.
- Add real execution only after product transport/status/ownership/idempotency gates pass, then evaluate scientific results and response quality.

The useful result today is narrower and concrete: Hermes's existing tool registry can dispatch BioMate's evaluation adapter and return validation feedback without replacing our validators or workflow executor.
