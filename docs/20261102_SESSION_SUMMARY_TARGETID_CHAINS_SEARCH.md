# Session summary, 2026-11-01 to 2026-11-02: target-ID, agent patterns, workflow chains, database search

Written for a reader with no background. Every number below was read from code, the database or a recorded run; "not verified" marks what was only built or inferred.

## 1. What was asked and what came out
| Theme | Outcome | State |
|---|---|---|
| BD supplement and capability audit | EN and ZH BD documents delivered earlier; audit and gap register in `20261101_BIOMATE_CAPABILITY_AUDIT.md`, `..._GAP_REGISTER_AND_TEST_PLAN.md` | done |
| Target identification fixes | per-target source links, offline snapshots, inline and run-output hospital data, drug-type suggestion (guidance only), citation existence check, time-split gold set | built and tested; novel-target discovery not shown (gold too small: 11 novel pairs at 2023-06-30) |
| Virtual Biotech (Science 2026) comparison | no released code; own building blocks exist (`map_reduce`, `corpus_fs`, router); Paperclip client built (needs a key we do not have); full ClinicalTrials.gov registry mirrored (609,551 studies); switch-like-gene prior tested on our own data | prior: direction agrees with the paper (risk ratios 1.07 / 1.18 / 1.17), smaller than published, survivorship bias; agent system not tested |
| Orchestration | seven separate control loops found; one model proposed: steps (workflow or capability), plans as chain DAGs, loops (campaign), human gates as a step property | design only |
| Workflow chains | 69 defined chains; none has a recorded run; 17 have an unresolvable step; 85 of 137 connections name a parameter the downstream workflow does not declare | audited; partly repaired |
| Vina bench scenario | chain `vina_virtual_screening_bench`, transforms, EGFR 1M17 data and scorer | built; **not run end to end** |
| Data sources and database search | registry 62 entries (60 live; Crossref and the local corpus index were already wired and are now declared); bioRxiv/medRxiv and ClinicalTrials.gov added; Open Targets and GEO recorded as live through dedicated tools; chat `query_database` tool added with the intent-driven `operation` | built and tested offline; dev deployment pending |

## 2. Key findings worth remembering
1. **Chains cannot pass data between steps as defined.** The executor passes an upstream output as `params[to_input]`; only 5 of 137 curated connection names matched a declared downstream parameter. Many real parameters are inline values (`smiles_list` as a JSON array, `box_center` as `[x,y,z]`) while the executor hands over file paths. A pre-launch binding check (fail early, clearly) and a transform registry (`smiles_file_to_json_list`, `pocket_json_to_box_center`) were added. Report: `20261101_WORKFLOW_CHAIN_AUDIT.md`; plan: `20261101_CHAIN_FIX_PLAN.md`.
2. **"696 workflows have a recorded real run"** means 336 `ok` plus 360 `ok_warnings` rows with the provisional flag off, from an internal audit that ran each workflow on test inputs (2026-06-09 to 2026-10-15). 685 of the 696 are Bioconductor wrappers; drug discovery has 3. It does not mean user runs. The meaning of "provisional" was not confirmed.
3. **Database lists disagree.** The connector UI lists 64 databases; 22 are searchable by the federated fan-out, 9 are reached only by dedicated tools or the research agent, 15 only appear in workflows, scripts or data files, 18 have no integration found (code search, not execution). See `20261101_DATABASE_LIST_UI_VS_BACKEND.md`.
4. **The optimised database search was not reaching the main chat.** `operation` = lookup / text / similarity (ChEMBL and PubChem by SMILES over the whole database, PDB by sequence) existed only in the connector tool set. A first chat tool was federated-only and ignored it; it was reworked to expose `database`, `operation`, `sources`. Only 2 of the 19 connector tools and 12 assistant tools overlap; `20261102_TOOL_SETS_UNIFICATION_PLAN.md` proposes one registry with per-surface flags.
5. **Failures were reported as "no results".** On dev, Semantic Scholar answers HTTP 429 (shared keyless limit) from inside the container; the federated fetcher swallowed every HTTP error and the fan-out listed the source as "ok, 0 results", and cached that answer for an hour. Fixed (commit after `a4e566d11`): a swallowed failure now becomes an error on that source, `sources_failed` is truthful, partial answers are not cached, and `SEMANTIC_SCHOLAR_API_KEY` is honoured when set. Without a key Semantic Scholar will keep failing on dev, visibly.
6. **Fixture-account hygiene.** A driver script briefly contained a hardcoded fixture password (blocked before committing; now read only from `E2E_FIXTURE_PASSWORD`). Three older docs still contain the password in clear text.

## 3. Deployment
Sync `b27f6d24` (full) completed healthy on dev (verified read-only: 70 chains, embeddings cover all 4,223 workflows, Galaxy answers). Commits after it (bioRxiv, ClinicalTrials.gov, `query_database`, manifest) await a second sync; another session was holding the sync lock at the time of writing, and the second sync is queued behind it.
Known issues in `scripts/sync_to_dev.sh`: the in-container DB copy step has a quoting error (host volume still serves the new DB); the embedding rebuild timeout (660 s) is tight; it refuses to run with uncommitted tracked source files.

## 4. Open items, in priority order
1. Second dev sync, then a read-only check that `clinicaltrials` and `biorxiv` answer on dev.
2. First dev run of the Vina chain: needs `E2E_FIXTURE_PASSWORD` in the environment; prediction already committed (`20261101_VINA_BENCH_RUN1_PREDICTION.md`).
3. Chain repairs not yet done: `andv_inhibitor_track_v1`, `bulk_rnaseq_de_analysis`, `rare_disease_multimodal_workup`, `bioc_bulk_rnaseq_de_v2`, and the retired docking step in `target_to_lead_full`. The DAG execution path does not apply transforms.
4. Tool-set unification (decisions listed in the plan).
5. Design: brief for Claude Design (`20261101_CHAINS_GATES_LOOPS_BRIEF_FOR_CLAUDE_DESIGN.md`) and a tutorial for survey, propose, measure; existing tutorials do not name any defined chain.
6. Paperclip needs a key (`PAPERCLIP_API_KEY`); without it the source is disabled and says so.
7. Radiology work (uncommitted, unverified) is on hold by request.
8. 18 UI-listed databases have no integration; OpenFDA and cBioPortal have free public APIs.

## 5. Not verified
No chain has been run end to end. The transforms were tested on files built from the workflows' code, not on real output. The LLM per-document reader (`corpus_fs/llm_map.py`) was tested with a fake model only. Live chat behaviour of the new `query_database` tool has not been observed. Spend: AWS compute used was small (a few spot-instance hours; no LLM spend).

## 6. Where things are
Docs: `docs/20261101_*`, `docs/20261102_*`. Code: `backend/lib/galaxy/ai/{target_id,corpus_fs,chain...}`, `backend/lib/galaxy/chain/`, `backend/scripts/{repair,add_vina_bench}_*.py`, `scripts/{audit,lint}_workflow_chains.py`, `scripts/source_registry_report.py`, `evaluation/{virtual_biotech,chain_bench/vina_egfr}/`. About 46 commits this session carry the co-author trailer.
