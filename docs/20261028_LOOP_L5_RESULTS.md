# Closed-loop paper — workstream 2 results log (2026-10-28)
Status at writing: **L5 is running (no result yet)**; this file records what was verified, what was found wrong, and what each arm uses of BioMate. Numbers are added only from aggregated result files.

## 1. Run status
| run | state |
|---|---|
| L3 (within-source, GBM, 420/420) | done; `results/l3_aggregate.json`: loop beats random in A (+176.7 [146.3, 208.9]) and B (+32.6 [15.7, 51.8]); knowledge arms uninterpretable (pooled-scale knowledge, chirality-blind features) |
| L4 | never produced results (spot instance i-0006de0766ec1d461 gone ~2 min after launch, 0 knowledge-arm files); folded into L5 |
| L5 baseline | running on i-0ebd278780579f12b (m6i.8xlarge spot, 32 processes, 810 tasks = 9 arms × 3 regimes × 30 seeds), results `s3://biomate-nextflow-work/cyclic_peptide/loop_retro/res5/`, flag `res5_done.flag`; aggregate with `aggregate_prior.py res5 results/l5_aggregate.json` |
| L6 product-chain arms | pre-registered; `rule_bm`/`fuse_bm` deferred (§3); `chain_exec` and KB-equivalence test not yet implemented |
| L7 LLM-in-the-loop replay | pre-registered only; depends on workstream 1 (v4 adapter, fine-tune routine) and workstream 3 (frozen lists) |

## 2. Audit findings (code, data, evaluation)
See manuscript_loop.md "Data and design audit" and `results/l5_label_audit.json`. Fixed in L5: chirality-aware fingerprints, PAMPA label column, source-standardised knowledge, seeded random tie-breaking in rule arms, regime C (near-duplicate-aware), second hit definition, pick provenance. Positive controls: `test_l5.py` (5 pass), including stereoisomers separable only with chiral features (chiral CV accuracy 0.75 — RDKit's chiral Morgan separates 48 of 64 isomers; blind features identical across all 64). Existing `test_loop_prior.py` (6) and `test_loop_par.py` (3) pass; the patched aggregator reproduces the committed L3 aggregate exactly. Not done: remaining audit of RNG streams across arms beyond reading (seeds are shared across arms, which keeps arms paired); the transductive-leak effect on loop outcomes is bounded by label sensitivity only (not re-run with online statistics).

## 3. What the BioMate chain and knowledge sources are (read 2026-10-28) and what each arm uses
Chain (`loop.py`, `loop_batch.py::run_round`, `physics_batch`, `execution_grader`, `graded_run_store`, `loop_grade_bridge`, `reward.py`): built around αvβ6 binding (proposer `gen_avb6`, RGD gate, `binding_dG` contract); `graded_run_store` rewards are execution tiers, not measured values; no permeability path; extension points `register_run_kind` / `register_contract`. Knowledge: `medchem_kb.physchem_for("cyclic_peptide")` → 2 statements (bRo5; chameleon permeability is conformational, 2-D descriptors miss it); `modality_heuristics` → N-methylation raises passive permeability (Biron 2008, T1, verified) — the only computable permeability rule = `K_nme`. Workflow DB (4,223 workflows): `membrane_permeability_prediction` (hand-coded linear TPSA/logP formulas, floors 0.01, never executed-validated; on this dataset the PAMPA output is at the floor for 42% of peptides, Caco-2 for 97%), `qsar_rf_model` (CV metrics only; cannot drive selection), cofold / MM-GBSA (binding).
**Product execution attempts (real runs):** run e1093517-2ad9-4420-8891-d2973f995342 (workflow_id "12868") failed at launch: `nextflow run /app`, `Missing project main script` (input_data). Run 9198fdac-a8da-4f58-b70f-6aba3acd68c7 (workflow_id = nextflow_path from search) executed but resolved to `drug_discovery/predict_admet_properties` and returned results for the default compounds, not the 5 submitted peptides (`smiles_list` not honoured). Search card and executed workflow disagree on path. These block a product-executed permeability signal; a bypass (my copy of a different formula) is not reported as the product's work.
| arm | standalone GBM loop | BioMate components ran | bypassed |
|---|---|---|---|
| random, fp, kn, resid_*, fuse_* (L5) | yes | none (standalone scripts) | whole chain, KB, workflow DB |
| rule_nme, rule_z (L5) | rule on RDKit descriptors | none | KB provenance layer (rule equals the KB's N-methylation heuristic by content, not by call) |
| rule_bm, fuse_bm (L6) | — | deferred | product workflow does not score submitted peptides (above) |
| chain_exec (L6) | fp loop + graded labels | execution_grader, graded_run_store, loop_grade_bridge (planned) | propose/revise, physics_batch, reward/DPO (no physics for a measured label) |
| LLM-in-loop (L7) | v4 | planned: KB D1/D3/D5 rules, cheap `score()` tier, execution grading | GPU physics tier (no admissible ΔG), DPO until audited |

## 4. Remaining gaps
L5 aggregate and manuscript numbers; chain_exec and KB-equivalence implementation (L6); product fixes needed for `rule_bm` (honour `smiles_list`; batch input beyond one env var; path consistency); L7 depends on workstreams 1 and 3; a proposed patch to the peer RSI manuscript is not written (it needs the L5 result first).
