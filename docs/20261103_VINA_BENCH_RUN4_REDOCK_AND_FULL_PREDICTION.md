# Vina bench: redocking control + full 296-compound run — pre-run review and prediction (written before the runs)

Date: 2026-11-03. Dev at `0b5656bcb`; the dev container's `docking_autodock_vina/main.nf` is byte-identical to the committed sharded version (md5 561336f5…).
Image `biomate/biomni-structure-to-drug:x86` = CI build `x86-bcd0c311201f` (fpocket 4.2.3, smoke-tested).

## Review of the sharded docking step (what the runs depend on)
- `DOCKING_AUTODOCK_VINA_WORKFLOW` parses `params.smiles_list` (the chain wires it as a JSON array string through
  `smiles_file_to_json_list`) and splits it into shards of `docking_shard_size` = 10. A non-JSON value becomes one shard (old behaviour).
- Each shard task: `PARAM_SMILES_LIST` = that shard's JSON; Vina uses `task.cpus`; outputs `shard_N_results.json`, `shard_N_output.txt`,
  `shard_N_qc_metrics.json`, `docking_poses/shard_N_pose_XXX.pdbqt`. Shards do not publish.
- `DOCKING_MERGE` concatenates shard results in shard order and publishes the usual `docking_autodock_vina_results.json`,
  `docking_autodock_vina_output.txt`, `qc_metrics.json` and `docking_poses/` — the files the chain executor, QC monitor and scorer read. A failed shard
  makes the merge exit 1 (no silent partial result).
- Receptor: waters and `site_ligand` (AQ4) removed before PDBQT preparation; box from the reference site (centre 22.014, 0.253, 52.794; size 25.7 × 20 × 20 Å).
- Silent-skip check: if `smiles_list` were empty the single shard docks nothing and the merge exits 1 — a hard failure, not a fake empty result.

## Run A — redocking positive control
One docking step, `smiles_list = [erlotinib]` (BDBM5446), receptor 1M17, `site_ligand` AQ4, box as above.
Pass criterion (scenario doc): heavy-atom RMSD of the top pose to the crystal erlotinib < 2.0 Å, computed by `score_run.py redock_rmsd`
(`nearest` mode, optimistic, symmetry-naive). The workflow's own `rmsd_vs_crystal_A` is NOT used: its reference is a SMILES-generated conformer, not the crystal pose.
**Prediction:** succeeds in 1 shard, about 1–3 min of Batch time; top-pose RMSD 1–3 Å (erlotinib's flexible methoxyethoxy tails often misplace while the
quinazoline core docks correctly). I give a pass (< 2.0 Å) roughly even odds.

## Run B — full library through the chain
Chain `vina_virtual_screening_bench`, `compound_library` = all 296 compounds (50 test actives + 246 decoys), 5 reference actives.
**Prediction:** pharmacophore filtering keeps roughly the same fraction as the 40-compound run (39/40), so about 250–296 ligands reach docking → 25–30 shards
run in parallel (subject to the Batch compute-environment cap). Docking wall time about 5–15 min, versus about 2 h serial. Enrichment: on 40 compounds
AUROC was 0.45 (chance); with 296 the estimate tightens. I expect AUROC 0.50–0.65 — Vina alone is a weak enricher for kinase inhibitors against
property-matched decoys; a value near 0.5 would mean the docking score adds nothing here and the bench needs a better scoring step, not a wiring fix.

## What would make the runs uninformative
Pharmacophore filtering removing most actives (it was built from 5 diverse references) — then the AUROC measures the filter, not docking. The scorer counts
filtered-out actives as misses; the per-step counts will be reported separately.
