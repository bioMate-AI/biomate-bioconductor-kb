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

## Results of run 4 (recorded after the runs)
- **Timing:** full chain 33 min (pocket 3, pharmacophore 2, ADMET 4.5, docking 23.5). Docking ran 29 shards of 10; only about 8 at a time because
  compute environment `biomate-nextflow-ce-v2` is capped at 48 vCPUs and each shard requests 6 (executor tier `process_medium` = 6 vCPU / 36 GB).
- **Full library (287 of 296 docked; 1 active filtered out):** AUROC 0.545, permutation p = 0.153, EF1% 1.97, EF5% 1.58. Within the predicted
  0.50–0.65 band and not distinguishable from chance.
- **Redocking control: FAIL.** Top-scored pose 5.77 Å from crystal erlotinib (heavy-atom RMSD, `nearest`); the only near-crystal pose (1.96 Å) ranked 9 of 9;
  the nine Vina scores span only −7.36 to −7.06.
- **Scorer defect found and fixed:** `_read_heavy_coords` stopped at any line starting with "END", which includes PDBQT `ENDROOT`, so it read 10 of 29 atoms.
  Fixed (stop only at `ENDMDL` or a bare `END`) with a regression test.

## Root cause found for the redock failure, and fix (run 5 prediction)
1M17 contains no hydrogen atoms, and receptor preparation (`obabel -xr`) added none, so the receptor PDBQT had no HD atoms. Vina recognises receptor
H-bond donors only through polar hydrogens, so the hinge Met769 N–H → erlotinib N1 hydrogen bond, which anchors quinazoline inhibitors, could not be scored —
consistent with near-flat scores and a misplaced top pose. Fix: `obabel ... -xr -p 7.4` (hydrogens for pH 7.4; the PDBQT writer keeps polar H), a hard
error if the receptor has zero HD atoms, and the polar-hydrogen count in the log. The old fallback that renamed the raw PDB to .pdbqt on any preparation
error is removed (it produced meaningless scores silently).
**Prediction for the redock rerun:** log shows several hundred polar hydrogens for the trimmed receptor; top pose RMSD drops below 2.0 Å (I give it
about 65%); scores spread more and become more negative (about −8 to −9.5 kcal/mol for erlotinib). If the top pose is still above 2 Å with donors present,
the remaining suspects are search depth (exhaustiveness 8 for a 10-rotatable-bond ligand) and the SMILES-built starting conformer, in that order.
