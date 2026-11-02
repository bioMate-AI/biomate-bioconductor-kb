# One tool definition for every surface: findings and plan

Date: 2026-11-02. Trigger: the intent-driven database search (`operation` = lookup / text / similarity, built 2026-07-19) reached only the connector tool set, not the main chat assistant.

## Findings (names compared in code on 2026-11-02)
| Set | Where defined | Count | Used by |
|---|---|---|---|
| Connector manifest | `backend/lib/mcp/tools_manifest.py` (canonical) -> `tools_manifest.json`, `connectors/chatgpt/openapi.json`, copy in `frontend/server/` | 19 | external MCP clients, ChatGPT connector, Open Claw (Slack/WeChat) |
| Main assistant | `BIOMATE_TOOLS` in `frontend/server/galaxy-assistant.ts` | 12 | the in-app chat |
| Agentic orchestrator | `frontend/server/orchestrator.ts` | 5 | nothing by default (`ORCHESTRATOR_MODE=agentic`) |

Only `search_literature` and `query_database` appear in both of the first two (`query_database` since 2026-11-02). The rest are different families:
the manifest holds execution and files (`run_workflow`, `get_run`, `watch_run`, `export_report`, `upload_file`, `resolve_accession`, `fetch_public_data`, `recall_memory`, ...);
the assistant holds reasoning-side tools (`run_code`, `identify_targets`, `write_review`, `search_my_data`, `list_data_sources`, `request_new_tool`, ...).
The same capability is named differently (`search_workflow` vs `search_workflows`) and the two `search_literature` definitions call different backend paths and take different parameters.
So the problem is not three copies of one list; it is that **capabilities have no single definition and no declared surfaces**, so an improvement made behind one tool (the DB-search operations) never reaches the others, and nothing detects it.

## Design
One registry of capabilities (extend `tools_manifest.py`, already canonical and already drift-tested): each entry has `name`, `description`, `input_schema`, `backend_path`, and `surfaces` = any of `assistant`, `connector`, `openclaw`. Each surface's tool list is generated from the registry (the manifest JSON already is; `BIOMATE_TOOLS` and Open Claw's list become generated too). Handlers stay in TypeScript, keyed by name, because the assistant's handlers are user-scoped proxies.
Rules enforced by tests: a capability present on two surfaces has one schema; every registry tool with `assistant` in `surfaces` has a dispatch case in both provider loops (a test of this kind exists); names of renamed duplicates are unified (`search_workflow` / `search_workflows`).
This is the capability registry of `20261101_ORCHESTRATION_OVERVIEW_AND_UNIFICATION.md` with surfaces added; it is the same registry the planner will use.

## Slices (each testable, none changes behaviour until its flag/commit)
1. **Inventory and drift tests (no behaviour change).** A test that lists every tool on every surface and fails when a name or schema diverges between surfaces without being declared; start by recording today's divergences as an explicit allow-list.
2. **Add `surfaces` to the registry** and generate the connector JSON as today; add a generated TypeScript module (`generated-tools.ts`) for the assistant from entries with `assistant` in `surfaces`; keep hand-written tools in place and migrate one by one, starting with `query_database` and `search_literature`.
3. **Unify the literature tool**: one schema, both surfaces, one backend path (`/api/literature/search`).
4. **Unify workflow search** (`search_workflow(s)`), then accession resolution into the assistant (it currently cannot resolve a GEO accession itself).
5. **Retire `orchestrator.ts` or fold it in** once the registry covers what it offers.
6. **Per-surface gates**: execution tools on the assistant need the human-gate field from the overview doc before they are exposed.

## Open decisions
- Whether the in-app assistant should get the execution tools (`run_workflow` and relatives) at all, or keep running workflows through its own panel flow. Exposing them changes chat behaviour materially.
- Whether Open Claw should keep inheriting the connector list or get its own surface flag (recommended: own flag).
