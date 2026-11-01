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

## Added later on 2026-11-01

| Item | Commit | State | Detail |
|---|---|---|---|
| Automatic conversion of a completed run's output (DESeq2, edgeR, limma, Cox, recurrence, dependency) | `4441e0649` | Tested | Route option `run_outputs`; reads only inside `TARGET_ID_RUN_OUTPUT_ROOT`. |
| T8 citation existence check and refusal | `25de7ce8a` | Tested, live 20/20 | PMID/DOI against NCBI and Crossref; nothing grounded gives an explicit refusal. Existence is not support. `20261101_CITATION_EXISTENCE_CHECK.md`. |
| T11 source counts | `773aabc5c` | Done | `scripts/source_registry_report.py`: 58 sources, 54 live, 21 reachable from chat. `20261101_DATA_SOURCE_COUNTS.md`. |
| T5 drug-type selector | `0d282fba2`, `f6a0f724a` | Partial, guidance only | Held-out accuracy 0.858 against 0.803 for always-small-molecule (intervals overlap); biologic recall 0.375. Route option `suggest_modality`, always `validated=false`. `20261101_TARGETID_MODALITY_SELECTOR.md`. |
| T9 time-split gold | `37d9e4dc0`, `0ca4dd97f` | Built, too small | 11 novel pairs (7 targets, one disease with two or more) at 2023-06-30, 1 at 2024-06-30, 0 at 2025-01-01. No novel-target claim can be tested or made. Built and smoke-tested on the dev host in `/tmp`, since removed. `20261101_TARGETID_TEMPORAL_GOLD.md`. |
| Chat tool | `4e51b9315` | Tested (12 vitest) | `identify_targets` passes `ranking_mode`, `validate`, `suggest_modality`; returns `validation_plan` and `modality_suggestions` with a note that they are not validated. |
| LLM-channel benchmark scripts v1-v6 | `de5b8d285` | Committed as found | Earlier untracked work from 2026-10-25. |

Not deployed: none of the above has been synced to dev. Deploying needs the pre-sync checklist and `sync_to_dev.sh`.

## Still open

- **Interface:** an evidence-links table component; the connector manifest (`connectors/chatgpt/openapi.json`) does not list the new `identify_targets` options.
- **T7, measurement:** the language-model channel has not been measured with a hospital-class open model (needs an endpoint).
- **T9:** a usable novel-target test needs more cut-offs, a pooled design across many diseases, or prospective tracking.
- **Radiology image analysis:** code exists but is uncommitted and unverified; it is not a verified capability.
- STRING has no offline snapshot (the full network file is large); offline deployments get the Open Targets evidence and
  any client or table channels.
