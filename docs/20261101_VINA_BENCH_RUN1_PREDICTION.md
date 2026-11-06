# Vina bench chain, dev run 1 (smoke): prediction written before the run

Date: 2026-11-01 (run executed overnight). Chain `vina_virtual_screening_bench` on dev, sync `b27f6d24`. Inputs: PDB `1M17` (fetched by id), 5 reference actives, a 40-compound smoke
library (10 test actives including the 5 approved drugs, 30 decoys; seeded subset of `library.smi`), staged in `s3://biomate-nextflow-work/chain_bench/vina_egfr/`.
Why a smoke set: docking is one serial process (about 4 CPUs, label `process_medium`, 4 h limit) and the chain executor stops polling a step after 3,600 s, so the full 296-compound library may not finish inside one step.

## What I expect, step by step
1. Pocket detection: completes and publishes `1M17_pockets.json` with several pockets. Uncertain whether the top-ranked pocket by druggability is the ATP site that holds erlotinib (I give it roughly even odds); if not, docking happens in the wrong place.
2. Pharmacophore filtering: completes and publishes `filtered_compounds.smi`. With five diverse reference actives the pharmacophore may be weak, so it may drop some of the 10 test actives (each dropped active counts as a miss).
3. ADMET: completes; its output does not gate docking (the chain description says so).
4. Docking: receives the box from the pocket handoff and the filtered list as an inline JSON array via the transforms; completes in roughly 10 to 40 minutes for 40 ligands (not measured before).
Handoff warnings: none expected. If a step fails, the most likely causes in order: the S3 input path not staged for the first-step parameter, a mismatch between the pocket transform output and the docking parameters, or a missing dependency in the container.

## Success criteria for this smoke run (not the bench result)
All four steps `succeeded`; docking results JSON present; the scorer runs; handoff warnings recorded. Enrichment on 40 compounds is reported but is not a result (too few compounds); the full-library run and the redocking positive control follow only if the smoke run passes.

## Cost
CPU Batch jobs only, no GPU. Cost and wall time are recorded from this run into the harness README (they were not estimated before).
