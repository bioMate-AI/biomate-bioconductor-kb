# P1 fix #1 — scope: wire the composer into the live `generate_workflow_unified`

**Date:** 2026-10-21 · **Status:** SCOPE ONLY (not implemented — hot endpoint; contracts + a
granularity-correct eval must be verified first). Implements `20261012` §4.

## Target (verified)
- Live path: `POST /api/ai_assistant/generate_workflow` → route handler
  `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py:3879` → calls the **method**
  `self.generate_workflow_unified(...)` (`:4031`).
- Method: `backend/lib/galaxy/ai/ai_assistant.py:4373` (**sync**). Entry log at `:4407`.
- The composer (`build_dag_plan`) currently lives only in the sibling `generate_workflow` method
  (`~779`), which the live route does NOT call → the enabled flag is inert.

## Contracts (confirmed on the same `AiAssistant` class)
- `self._looks_like_multi_task(query, user_id, session_id) -> bool` (`:620`, cache-backed, sync).
- `self.task_decomposer.decompose_request(request: UserRequest, parsed_intent: dict) -> List[Task]`
  (`task_decomposer.py:136`) — **needs an intent parse + a `UserRequest`** first (via
  `self.intent_parser`); NOT a one-arg `decompose(query)`. Mirror how `generate_workflow` builds its
  `tasks`.
- `self._resolve_task_to_workflow` (`:810`), `self._workflow_io_types` (`:833`),
  `self._extract_input_refs` (`:844`) — all present on this class.
- `decomposed_dag.build_dag_plan` / `bind_shared_inputs` / `to_pipeline_card` — pure, imported locally.

## Proposed hook (sketch — insert early, ~after :4407, before the search-first flow)
```python
import os as _os
if _os.environ.get("BIOMATE_MULTITASK_DAG_ENABLED","").strip().lower() in ("1","true","yes","on"):
    try:
        if self._looks_like_multi_task(user_intent, user_id=user_id or ""):
            parsed = self.intent_parser.parse(user_intent)            # confirm API
            req    = UserRequest(...)                                  # build as generate_workflow does
            tasks  = self.task_decomposer.decompose_request(req, parsed)
            if tasks and len(tasks) >= 2:
                from .decomposed_dag import build_dag_plan, bind_shared_inputs, to_pipeline_card
                dag = build_dag_plan(tasks, self._resolve_task_to_workflow,
                                     type_provider=self._workflow_io_types)
                if dag:
                    dag = bind_shared_inputs(dag, self._extract_input_refs({"datasets": uploaded_datasets}))
                    return {"success": True, "execution_mode": "dag",
                            "workflow": to_pipeline_card(dag),
                            "message": f"Prepared a {len(dag['steps'])}-step plan with dependencies."}
                # dag is None → fall through (never a half-built plan)
    except Exception as exc:
        log.warning(f"[MultiTask] unified composer hook failed ({exc}) — single-workflow fallback")
    # fall through to the existing single-workflow search-first path
```
**Fail-safe:** flag off, not multi-task, <2 tasks, any unresolved/handoff-miss, or any exception →
byte-for-byte the current single-workflow path.

## RISKS to clear BEFORE implementing (why this is scope-only)
1. **Return-shape compatibility (highest).** The route handler post-processes the result
   (pilot suggestion, N4 WorkflowSession save, citation metadata `:3111`, parameter_metadata
   `:4218`). A DAG result carries `workflow`/`execution_mode:'dag'` and NO `workflow_ga`. The route
   already tolerates missing `parameter_metadata` ("e.g. generate_workflow_unified path", `:4218`),
   and the frontend renders `execution_mode:'dag'` (per `20261012`) — but the N4 session-save and
   citation path must be confirmed not to assume `workflow_ga`. Trace `:4031–4260` before enabling.
2. **Decompose wiring.** `decompose_request` needs intent-parse + `UserRequest` — more than a
   one-liner; replicate exactly what `generate_workflow` does so behaviour matches.
3. **Hot endpoint discipline.** Unit-test the branch hermetically (injected resolver/type_provider,
   assert fail-safe fallthrough on every miss) per the pre-sync checklist; the Python module-load
   check (`import …webapps.galaxy.api.ai_assistant`) must pass (needs a full env — it does not import
   offline here: missing `beaker`).
4. **Measure on the RIGHT granularity.** Do NOT judge this with `decomposition_real` (GTN
   tool-chains; see `20261021_DAG_RESOLUTION_COVERAGE_RESULT.md`). Author a small multi-nf-core-
   **workflow** eval (requests chaining whole workflows) and gate the enable on it.

## Related: semantic-handoff dedup (item C) — deferred, with reason
`type_satisfies` + `_TYPE_ALIASES` are currently duplicated in `decomposed_dag.py` (fix #2) and
`workflow_chain.py`. The proper dedup (one shared pure module, e.g. `galaxy.chain.type_match`) is
deferred because: (a) making `decomposed_dag` import a `galaxy.*` module breaks its **standalone**
unit-test import offline (the test imports `decomposed_dag` top-level, avoiding the heavy `galaxy`
package); (b) `workflow_chain` does not import offline (`beaker`), so a repoint there can't be
verified here. Do the extraction + repoint in a full Galaxy env, with a drift-guard test asserting
the two tables are identical until then.
