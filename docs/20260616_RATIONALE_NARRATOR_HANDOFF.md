# Chain narrator rationale_id emission — integration handoff

Date: 2026-06-16
Branch: `bioc/v2-qc-audit-panel` → `integration/next-phase`

## Status

All scaffolding for the design-faithful `(why?)` anchor is shipped to
`integration/next-phase`:

- **Backend table**: `rationale_registry` (24 bioc rows). Created lazily
  by `backend/scripts/populate_rationale_registry.py`.
- **Backend endpoint**: `GET /api/rationale/{rationale_id}` →
  `nextflow_executor.py:5628` (commit `841d3b9fa0` on remote). Returns
  `{}` on miss; frontend hides the anchor.
- **Backend curation pipeline**: `backend/config/rationale_mapping.yaml`
  (88 phase rows, awaiting scientific-lead `confirmed: true` per row) +
  `docs/20260614_RATIONALE_GAP_TRACKER.md` (44 DOI-collection rows).
- **Frontend component**: `<WhyAnchor rationaleId="…">` mounted on every
  `chat_progress` message in `chat-message.tsx`. Renders nothing when
  endpoint returns empty.

## The one missing wire

When the chain runner emits `workflow.phase_started` for a real chain
run on dev, the `technical` dict needs to include a `rationale_id`
field, e.g.:

```python
_narrate_chat(invocation_id, "workflow.phase_started",
              {"phase_name": short_name,
               "rationale_id": f"{chain_name}:{phase_letter}"})
```

Without this field, the new endpoint is correct + the frontend is
ready, but no chain run on dev surfaces a `(why?)` anchor.

## Where to add it

`backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py:2444-2455`
— inside the `seen_phase_started` block that fires
`workflow.phase_started`.

The block currently has:

```python
if process_name and process_name not in seen_phase_started:
    seen_phase_started.add(process_name)
    try:
        _narrate_chat(
            invocation_id,
            "workflow.phase_started",
            {"phase_name": _short_phase_name(process_name)},
        )
    except Exception as exc:
        log.debug("[QC Monitor] phase_started emit failed for %s: %s", process_name, exc)
```

Add `"rationale_id": _resolve_rationale_id(invocation_id, process_name)`
to the technical dict.

## What `_resolve_rationale_id` needs

```python
def _resolve_rationale_id(invocation_id: str, process_name: str) -> Optional[str]:
    """Map a Nextflow process_name → 'chain_name:phase_letter' if this
    invocation is a chain run. Returns None for non-chain runs (one-off
    workflows) — frontend WhyAnchor hides cleanly on empty."""
    # 1. Look up the chain that owns this invocation. Source TBD —
    #    likely execution_runs.workflowName (PostgreSQL via the existing
    #    Galaxy DB shim) OR _runs[run_id]['chain_name'] if the chain
    #    composer stamps it at submit time.
    # 2. Resolve process_name → chain step order. Two viable routes:
    #    a. Stamp a process_name → step.order map at chain submit
    #       (composer knows both).
    #    b. Fuzzy match process_name against chain.steps[].workflow_name
    #       at lookup time.
    # 3. Return f"{chain_name}:{chr(ord('A') + step.order - 1)}".
```

## Integration boundary

This change requires DB read from inside the polling thread (the
`_poll()` closure runs on a daemon thread, no FastAPI request scope).
The existing `_runs` in-memory map is the cheapest source if the
composer stamps `chain_name` there at submit. Otherwise PostgreSQL
read is needed — verify the connection-pool semantics in that thread
context before adding.

## What this unblocks

Once shipped, the bioc tutorial demo + any real bioc chain run on
dev will show the `(why?)` anchor on each phase-start chat line. The
24 already-populated `rationale_registry` rows immediately go live.
Scientific-lead curation of the 44 mapping-only + 44 gap rows
(`rationale_mapping.yaml` + `RATIONALE_GAP_TRACKER.md`) feeds the
remaining 88 rationale_ids — those go live as each row is `confirmed:
true` and `populate_rationale_registry.py` re-runs.

## What I'm NOT changing

I'm not editing `_poll()` myself because:
- It runs inside a long-lived polling thread, error budget low
- DB layer crossing from that thread context needs the owner to
  confirm pool semantics
- Wrong fuzzy-match in `_resolve_rationale_id` would surface wrong
  rationale text (worse than no anchor)

Owner of `nextflow_executor.py` chain monitor should add the
`_resolve_rationale_id` helper + the one-line addition above. Estimated
~1 BE-day with proper testing.
