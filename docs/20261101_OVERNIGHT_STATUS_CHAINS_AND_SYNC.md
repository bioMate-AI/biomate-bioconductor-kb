# Status after the overnight session: chains, sync, and what is waiting on a person

Date: 2026-11-01 (late). Authoritative companions: `20261101_CHAIN_FIX_PLAN.md`, `20261101_VINA_SCREENING_CHAIN_BENCH_SCENARIO.md`, `20261101_VINA_BENCH_RUN1_PREDICTION.md`.

## Done and committed
| Item | Commit |
|---|---|
| W1 strict binding check (fail before launch when a connection names an undeclared downstream parameter) | `0ad80b027` |
| W2 repair spec and script (5 priority chains; extended to pin Vina) | `e322824ab`, `4f7f69544` |
| W3 chain lint + pre-sync checklist step 3b (required-clean = vina bench, drug_discovery_screening, admet-gated) | `0369c6859`, `20e291fe8` |
| B1 transform registry (`smiles_file_to_json_list`, `pocket_json_to_box_center`) and executor support | `8f1f32b74` |
| B2 chain `vina_virtual_screening_bench`; two chains repointed to `docking_autodock_vina` | `4f7f69544` |
| B3 EGFR 1M17 scenario data and scorer (BindingDB actives, ZINC250k decoys; ChEMBL and DUD-E were unreachable) | `e53ab97af` |
| Dev sync of all of the above | sync `b27f6d24`, result healthy |

## Dev verification (read-only, after the sync)
The container's DB holds 70 chains including `vina_virtual_screening_bench`; `drug_discovery_screening` and `drug_discovery_admet_gated_screening` use `docking_autodock_vina`. Embeddings cover all 4,223 workflows. Galaxy answers 200 on port 8081.

## Waiting on a person
1. **Dev run 1 of the Vina chain has not been executed.** The driver (`evaluation/chain_bench/vina_egfr/run_on_dev.py`) needs the shared fixture login. The password is deliberately not stored in the repository and `E2E_FIXTURE_PASSWORD` is not set in this environment. An attempt to run the driver was blocked by the session's permission check, and no workaround was attempted. To run it: `export E2E_FIXTURE_PASSWORD=...` then
   `python3 evaluation/chain_bench/vina_egfr/run_on_dev.py --actives 10 --decoys 30 --out /tmp/vina_run1`
   (the prediction is committed first, as the project rules require). In a Claude Code session, prefix the command with `!` so it runs in the session.
2. Decisions listed in the chain fix plan: whether to add a warn-only switch for the strict binding check; whether to build a transform for ADMET results to a SMILES list so ADMET can gate docking; what to do with `target_to_lead_full` (its `structure_prediction_docking` step has no executable workflow).

## Known issues found during the sync (not changed)
- `scripts/sync_to_dev.sh` around line 851: the step that copies the DB into the running container has a quoting error (`"{{.Names}}"` inside a double-quoted `bash -c` string) and fails with a syntax error. The host volume `/opt/biomate/galaxy_db` is mounted at `/app/database`, so Galaxy still read the new DB (verified), but the in-process copy step does nothing.
- The embedding rebuild step ran 666 s against its 660 s `timeout`, was killed and printed "embedding rebuild failed"; the embeddings file nevertheless covers all 4,223 workflows. The timeout is tight on a busy host.
- The sync refuses to run with uncommitted tracked source files; two connector files were committed (`52bfa0e8c`, `b27f6d24f`) so it could proceed, which also shipped the user's in-progress connector flow.
- `docs/20260701_E2E_USE_CASES_*.md` and `20260719_CONFERENCE_DEMO_PLAYBOOK.md` contain the fixture password in clear text, contrary to the project rule; removing it is a decision for the owner.

## Not verified
No chain has been run end to end. The transforms were tested on synthetic files built from the workflows' code, not on real pocket-detection output. The DAG execution path does not apply transforms.
