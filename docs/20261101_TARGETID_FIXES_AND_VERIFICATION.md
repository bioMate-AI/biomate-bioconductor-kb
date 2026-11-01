# Target identification: gap fixes and verification (2026-11-01)

Closes the target-identification gaps in `docs/20261101_BIOMATE_GAP_REGISTER_AND_TEST_PLAN.md` that can be closed in
the backend and the HTTP route. Items that need the chat client, the user interface, a model endpoint or new data are
listed at the end.

## What changed (all under `backend/lib/galaxy/ai/target_id/` and `webapps/galaxy/api/target_id_api.py`)

| Gap | Change | Evidence |
|---|---|---|
| T3 per-target source links | Every ranked target carries `evidence_links`: for each channel, the kind (public source, hospital data, model judgment), a URL where one exists, and a label. Open Targets links use the Ensembl id and the disease (`platform.opentargets.org/evidence/<ENSG>/<EFO>`); STRING links use the `cgi/network` form; language-model scores are labelled "model judgment, no citation"; client data is labelled "hospital data: <label>". Table provenance no longer exposes server paths | Live melanoma run: all five top targets show both links; the Open Targets link returns 200 and the STRING link returns 200. The `/network/<id>` form returns 403 to non-browsers, so the working form is used |
| T2 network channels in the live route | The orchestrator now runs in two stages: stage 1 (no seeds needed), then channels that need seed genes (STRING, pathway) seeded with the primary channel's top genes. STRING is in the default set when a disease is given; pathway when `TARGET_ID_GMT_PATH` is set. A seed-to-seed option gives the top genes their own network corroboration (without it, no top gene could be corroborated). Ranking stays Open Targets-primary, so expansion genes cannot dilute it | Live melanoma run: `channels_run = [genetics_ot, ppi_string]`, 20 seeds from Open Targets, top five "corroborated", expansion genes absent from the ranking |
| T1 hospital data as an evidence channel (backend) | New `client_data.py`: six adapters (over-expression in tumour, adverse survival association, recurrent alteration, dependency, cell-type specificity, surface expression) with written formulas, column mapping, row limits and actionable errors; rows are sent inline. Reliability weight `client_*` = 0.8 (a stated prior, overridable). New `ranking_mode`: `auto` keeps the Open Targets-primary default; `integrated` lets client data move the ranking | Unit tests with exact expected scores; live: a synthetic client gene moves from rank 19 (auto) to rank 1 (integrated) |
| Security: arbitrary server file read | `tables` paths are accepted only inside `TARGET_ID_TABLE_ROOT`; symlinks and `..` escapes are refused; only whitelisted options pass through. Without a root, server tables are disabled | Tests for traversal, absolute paths, symlink escape, extra options |
| T6 restricted network | Open Targets snapshots (`snapshot_open_targets` tool; `TARGET_ID_SNAPSHOT_DIR`, `TARGET_ID_OFFLINE=1`): offline mode uses only the snapshot; a live failure falls back to it; every snapshot result is labelled with its date and why it was used; missing snapshots list what is available. New `GET /api/target-id/status` lists the hosts a deployment must allow and what works offline. STRING is live-only and is skipped offline | Live: a real snapshot written, then an offline run with the network blocked returned the same top genes, labelled "snapshot" |
| T7 (parsing part) language-model channel with reasoning models | Robust extraction of the JSON answer (reasoning blocks, fences, trailing prose, braces in strings) and one retry with a doubled token budget (capped) when no JSON comes back | Tests for each output shape, the retry and the cap |
| T4 nominate-then-validate (route part) | `validate=true` returns the validation plan for the top targets, fail-soft | Route test |

## Tests

New: `evidence_links_test` (7), `client_data_test` (10), `seed_stage_test` (5), `llm_parse_test` (4),
`target_id_api_route_test` (8, with a stand-in for Galaxy's router because the full Galaxy environment is not installed on
the test machine). Existing suites all pass: data_channels (updated to the intended new default set), network_channels,
validation, smoke, demonstration, clinical_arm, chat_contract. The package imports under Python 3.9 (standalone) and every
changed file compiles under 3.9. Run: `PYTHONPATH=backend/lib python -m galaxy.ai.target_id.<name>_test`.

## Deployment settings

`TARGET_ID_TABLE_ROOT` (enable server tables, confined to that folder), `TARGET_ID_OFFLINE=1`, `TARGET_ID_SNAPSHOT_DIR`,
`TARGET_ID_GMT_PATH` (pathway channel). `GET /api/target-id/status` reports what is configured.

## Still open (not done here)

- **Chat and UI wiring:** the chat tool must pass `client_tables`, `ranking_mode` and `validate` (the chat files have
  another session's uncommitted edits, so they were not touched); the interface needs an evidence-links table.
- **T1, automatic conversion:** the adapters take a table; reading a completed analysis run's output file and building the
  table is the remaining step, and it needs the run store and the chat or interface side.
- **T7, measurement:** the language-model channel has still not been measured with a hospital-class open model
  (needs an endpoint). **T5** drug-type selector, **T8** literature refusal and reference-existence check, **T9** time-split
  gold for novel targets, **T10** connector manifest and chat reply contract, **T11** source-count script.
- STRING has no offline snapshot (the full network file is large); offline deployments get the Open Targets evidence and
  any client or table channels.
