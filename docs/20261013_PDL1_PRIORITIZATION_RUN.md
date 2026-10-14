# PD-L1 G1 prioritization — cofold + MM-GBSA run

**Date:** 2026-10-13 · Ranking the 13 PD-L1 blockade candidates (+ verified control) before ordering, via the
canonical physics discriminator: Boltz-2 cofold (cyclic) into PD-L1 → MM-GBSA rescore on the shared ΔG scale.

## Run
- **Cofold:** RUNID `cofold-v2-5o45-20261014T004510Z`, instance `i-0bd69d0c648c706d3`, g5.2xlarge (A10G, on-demand
  — spot capacity-exhausted), TARGET=5o45 (PD-L1 IgV, chain R), NO_KERNELS=1, 14 peptides, 3h deadline, self-terminating.
- **Peptides:** G1-01..10 + K-01/02/05 + **CTRL-5O45-pep71** (A2 positive control = 5O45 native macrocyclic
  peptide-71, RCSB chain B `PHE-MEA-9KK-SAR-ASP-VAL-MEA-TYR-SAR-TRP-TYR-LEU-CCS-GLY`, canonical approx `FFKGDVFYGWYLCG`).
- **Receptor/control provenance:** PDB 5O45 (PD-L1 + macrocyclic peptide-71), RCSB-fetched — not fabricated.

## Honest caveats
- Boltz takes canonical 20-AA → ncAA fold as nearest canonical (2Nal→F, dP→P, NMe dropped). First-pass ranking
  approximation; the real-stereochem molecule is what gets ordered/assayed. (A4 full-stereochem scoring is a later refinement.)
- Cyclic-peptide docking/scoring is imperfect; the control anchors admissibility (A2) — if the pipeline does not
  rank CTRL-5O45-pep71 among the stronger binders, the candidate ranking is not trusted.

## Next (on cofold completion)
1. Verify fold: 14/14 CIFs + ipTM; control folded.
2. MM-GBSA pool: `DESIGNS_S3=.../complexes TARGET=5o45 bash launch_mmgbsa_pool.sh`.
3. Rank by ΔG (+ ipTM), validate control, select top candidates to order. Record in this doc.

## Status log
- 2026-10-14T00:45Z — cofold launched (on-demand A10G); monitoring.
