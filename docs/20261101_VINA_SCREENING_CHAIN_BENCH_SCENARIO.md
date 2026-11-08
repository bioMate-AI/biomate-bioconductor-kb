# Vina virtual-screening chain built on a real bench scenario

Date: 2026-11-01. Follows `20261101_CHAIN_FIX_PLAN.md` and `20261101_WORKFLOW_CHAIN_AUDIT.md`. Decision (user): docking steps use `docking_autodock_vina`; the retired
`structure_prediction_docking` is dropped. Build the chain around real bench scenarios.

## Interpretation (stated so it can be corrected)
A bench scenario = a real target, real inputs a scientist would hold, and a known answer the chain's output can be checked against. Scenario 1 (this build): hit finding on a
structurally characterised target.
- Target: EGFR kinase domain, PDB 1M17 (co-crystal with erlotinib).
- Known actives: approved/clinical EGFR inhibitors (erlotinib, gefitinib, lapatinib, afatinib, osimertinib, ...), SMILES from ChEMBL.
- Decoys: property-matched, non-binding compounds (DUD-E EGFR decoy set, or a documented fallback).
- Success checks (the validation harness): (1) positive control: re-dock erlotinib into 1M17, heavy-atom RMSD to the crystal pose < 2.0 A; (2) enrichment: actives rank above decoys,
  report AUROC and EF1% against a random baseline; (3) every chain step finishes with its declared outputs handed on without manual edits.
Later scenarios (not in this build): ADMET triage of a lead series with measured hERG/CYP data; a lead-optimisation round against a campaign.

## Chain `vina_virtual_screening_bench`
pocket_detection_druggability (pdb_input 1M17) -> pharmacophore_filtering (reference_actives, compound_library) -> predict_admet_properties -> docking_autodock_vina -> ranked hits.
Optional later steps (GROMACS MM-GBSA, REINVENT4) stay out of this chain until their handoffs are solved.

## Why handoffs need transforms
Downstream parameters are often inline values while the executor passes file paths (`smiles_list` is an inline JSON array; `box_center` is `[x,y,z]`). A connection may carry an optional
`transform` drawn from a small registry; nothing is guessed:
- `smiles_file_to_json_list` (file of SMILES, one per line or a CSV column -> JSON array string);
- `pocket_json_to_box_center` (pocket detection JSON -> `box_center` `[x,y,z]` and `box_size`), selecting the top-ranked pocket, with the choice reported.
Interface: `backend/lib/galaxy/chain/transforms.py`: `REGISTRY: Dict[str, Callable]`; `apply(name, artifact_path, args) -> value` raising `TransformError` with a clear message.
Connection form: `{"from_step":2,"from_output":"filtered_smiles","to_step":3,"to_input":"smiles_list","transform":{"name":"smiles_file_to_json_list","args":{}}}`.
The binding check treats a connection with a registered transform as bound when `to_input` is a declared parameter; an unknown transform name is a problem.

## Workstreams (parallel, disjoint files)
| Id | Work | Files | Acceptance |
|---|---|---|---|
| B1 | Transform registry and executor support: apply a connection's transform in `_apply_connection_handoffs`; binding check recognises transforms; offline tests | `backend/lib/galaxy/chain/transforms.py`, `test_transforms.py`, small edits to `workflow_chain.py` and `binding_check.py` | transforms pass tests on realistic upstream files; a failing transform fails the step with a clear message before launch of the next job |
| B2 | Chain definition: read the four workflows' real output files and parameters; write `chain_repairs.json` entries / a seed script for `vina_virtual_screening_bench`; repoint `drug_discovery_screening` and `drug_discovery_admet_gated_screening` to `docking_autodock_vina` with correct connections | `backend/config/vina_bench_chain.json`, `backend/scripts/add_vina_bench_chain.py`, test; edit `chain_repairs.json` entries for the two chains | `lint_workflow_chains.py` passes for the three chains (extend REQUIRED_CLEAN in W3's constant for them); every non-file handoff names a registered transform |
| B3 | Scenario data and validation harness: EGFR 1M17 PDB, actives from ChEMBL, decoys, provenance manifest; `evaluation/chain_bench/vina_egfr/` with the harness that computes redock RMSD, AUROC, EF1% (offline-testable with synthetic scores); run instructions for dev | `evaluation/chain_bench/vina_egfr/*` | data files with licence/provenance; harness tests pass; no run on the laptop beyond tiny unit tests |
Then W4: sync (user approval) and run the chain on dev with a written prediction; scoring by the harness.

## Rules
No guessed mappings: each transform and connection is justified from the workflows' real files. Docking and screening compute runs on dev/Batch or EC2 spot, not the laptop. Nothing syncs without the user's approval.
