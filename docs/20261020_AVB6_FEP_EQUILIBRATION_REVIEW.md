# αvβ6 FEP control-edge — short equilibration review (before the production ΔΔG)

**Date:** 2026-10-20 · Internal. Review-before-spend note for the SHORT equilibration that validates the
fully-parameterized head-to-tail cyclic junction (and the flagged CMAP omission) under dynamics BEFORE we
commit ~2 GPU-days to the per-λ production ΔΔG. User chose option (a): equilibrate first, then a separate go.

## What runs (equilibration ONLY — not production FEP)
One spot-GPU Batch job (`biomate-gpu-spot-queue` / `biomate-gromacs-cu12-gpu`), both legs sequentially:
- **EM** from the staged self-contained `em.tpr` → `NVT` 200 ps (position-restrained, V-rescale 300 K) →
  `NPT` 500 ps (Parrinello-Rahman 1 bar). mdp templates `fep/mdp/{nvt,npt}.mdp`.
- Dispatched by `cyclic_llm/fep_batch.py --equil --submit` (`_equil_command`, a single-string container
  command — the image ENTRYPOINT is `/bin/bash -c`). The forcefield `charmm36m-mut.ff` is staged under
  `in/ff/` and the absolute pmx-mutff `#include` paths in `fep.top` are rewritten to relative at runtime
  (the GPU image has no pmx, so grompp needs the staged ff). **NO per-λ HREX, NO alchemical production.**

## Cost / wall-clock (modest, bounded)
- Solvent leg (~5.3k atoms): EM+NVT+NPT ≈ a few minutes on one GPU.
- Complex leg (~205k atoms): ~700 ps total ≈ **~0.5–1.5 GPU-hours** (g5/g4-class).
- **Total ≈ 1–2 GPU-hours, one spot GPU, ≈ $0.30–2.** Self-terminating. Spot only; no capacity → RUNNABLE
  until capacity (correct, no spend). Contrast: the production ΔΔG is ~2 GPU-days — this gate is ~1% of that.

## Acceptance criterion (checked post-equilibration on the uploaded edr/gro/logs)
**Junction OK** (proceed to ΔΔG) requires, for BOTH legs:
1. **Completion:** `npt.gro` produced; markers show `<leg>:EQUIL_OK`.
2. **No instability:** `LINCS_WARN=0` and `FATAL=0` across em/nvt/npt logs; no `nan`/`inf` in the potential.
3. **Energies physical:** `gmx energy` → Potential finite and negative (no blow-up); **Temperature ≈ 298–302 K**;
   Pressure finite (fluctuating around 1 bar); **Density ≈ 1000 kg/m³** for the solvated boxes.
4. **Geometry sane (post-hoc on `npt.gro`):** the head-to-tail amide C(last)–N(first) bond ≈ **1.33 Å**
   (0.13–0.14 nm) and the junction angles near backbone norms; peptide RMSD vs the start **bounded**
   (≲ 0.2–0.3 nm, no progressive drift), i.e. the macrocycle stays closed and intact.

**"Needs CMAP" signal** (do NOT proceed; add junction CMAP first): the run survives but shows **localized
strain at the junction** — the two junction residues' φ/ψ drift to unphysical values, the junction bond/angle
sit visibly outside normal ranges, or peptide RMSD is driven by distortion concentrated at the junction —
indicating the omitted backbone CMAP at those 2 residues matters. A hard **LINCS explosion / fatal blow-up
localized to the junction atoms** is the extreme form of the same verdict.

If the junction holds (criteria 1–4 met, no "needs CMAP" signal), the control-edge FEP setup is dynamics-
validated and the full ΔΔG is scientifically safe to run — pending the user's explicit go. If it shows the
CMAP signal, the correct next step is adding the junction CMAP terms (not forcing the ΔΔG).

## Guard state
`EQUIL_CMD_READY=True` (this job). `MDRUN_CMD_READY=False` — the **full per-λ production ΔΔG stays guarded**
and is NOT submitted. Candidate-ladder edges (M7/M11) remain held.
