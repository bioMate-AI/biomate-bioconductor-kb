# FEP finalist tier — status (2026-09-20): toolchain stood up, MD stability pending

The FEP capstone (the ~1 kcal/mol size-bias-free binding arbiter that MM-GBSA cannot be — see
`COMMITTEE_REVIEW.md`, manuscript §3.11) was **started, validation-first**: stand up an alchemical
free-energy pipeline and prove it on a KNOWN answer (ethanol hydration free energy, FreeSolv ≈ −5.0 kcal/mol)
before trusting it on binding. Tool: `fep_hydration_poc.sh` (openmmtools AbsoluteAlchemicalFactory +
ReplicaExchangeSampler + MBAR), GPU/CPU spot launcher `launch_fep_poc.sh`.

## What is DE-RISKED and working (5 blockers cleared, each a fast/cheap failure)
1. dependency stack: openmm + openmmtools + openff-toolkit + openmmforcefields + pymbar install cleanly.
2. system build: ethanol (GAFF-2.11/AM1-BCC) solvated in TIP3P (744 atoms) via `SystemGenerator`+`Modeller`.
3. alchemical construction: `AbsoluteAlchemicalFactory` + 12-state λ schedule (elec 1→0 then sterics 1→0).
4. replica-exchange + MBAR wiring (`ReplicaExchangeSampler`, `MultiStateSamplerAnalyzer`).
5. infra: forced **CPU** platform to dodge the DL-AMI `CUDA_ERROR_UNSUPPORTED_PTX_VERSION` (same known issue
   as the MM-GBSA runs); pre-minimization + NVT + 1 fs added.

## The BLOCKER — ISOLATED by the diagnostic run (2026-09-21)
A diagnostic harness (minimize → gradual heat 10→298 K → 10 ps NVT on the PLAIN system, with a finite-energy
gate, before any alchemy; + exact PME; + nan-log sync) pinned the cause:
- **The PLAIN solvated system is STABLE** — minimized to E ≈ −2881 kcal/mol and passed equilibration without
  tripping the finite-energy guard. So the NaN is **NOT** basic MD/system setup.
- **The NaN is ALCHEMY-SPECIFIC, in the sterics-decoupling region** (replica at state 10, sterics ≈ 0.1),
  and persists even with exact PME + an equilibrated start + per-state minimization. Earlier wandering
  (states 8/0/3) was pre-equilibration noise; with the plain system stabilized it localizes to the
  near-decoupled-sterics windows.
- **Root-cause class: soft-core Lennard-Jones sterics-decoupling instability** — a known, non-trivial FEP
  setup problem, not a one-liner. Diagnostic-first isolation succeeded; blind relaunch stopped per discipline.

### Sharpened next-session fixes (sterics decoupling)
1. Add more λ windows in the sterics-off region (e.g. 0.1/0.05/0.025/0.0 instead of one 0.1→0 jump).
2. Tune openmmtools soft-core (`softcore_alpha`, `softcore_beta`) and/or set `annihilate_sterics` explicitly.
3. Add a weak ligand positional restraint during decoupling (keeps the vanishing ligand from drifting into a clash).
4. Smaller timestep (0.5 fs) only in the decoupling windows.
5. Strongly consider a turnkey protocol — `openfe`/`femto`/AToM ship validated soft-core schedules and would
   likely sidestep this tuning entirely (recommended first move next session).

## Concrete next-session debugging plan (in order)
1. **Read the saved `nan-error-logs`** (openmmtools dumps positions+integrator state at blow-up) — identify
   which atoms/forces diverge (ligand self-overlap? a specific water? the alchemical soft-core term?).
2. **Test the PLAIN (non-alchemical) system stability first**: minimize → gradual heating (e.g. 10→298 K over
   100 ps) → short NPT equilibration, confirm it's stable *before* adding alchemy. Launching Langevin at 298 K
   directly from a cold minimized structure is a prime NaN cause; add equilibration + per-state relaxation.
3. **Verify the alchemical electrostatics soft-core**: confirm `alchemical_pme_treatment`/soft-core settings;
   NaN at the elec-decoupling state (3) suggests a charged-particle singularity — consider decoupling (not
   annihilating) electrostatics, or `AbsoluteAlchemicalFactory(alchemical_pme_treatment='exact')`.
4. **Sanity-check GAFF/AM1-BCC charges** on ethanol (net charge, obvious errors).
5. Start smaller: 2–3 λ states, `n_steps` short, confirm NO NaN, then scale to 12.
6. Consider an established turnkey alternative (e.g. `femto`, `openfe`/OpenFreeEnergy, or AToM-OpenMM) instead
   of a hand-assembled openmmtools sampler — may sidestep the stability tuning entirely.

## When the pipeline validates (reproduces ≈ −5 kcal/mol)
Then extend to the two real applications, in order:
- **Binding ABFE** on the dual-optimal picks (`GGPLLGR`, `GPFVPGL`, `FVVGNPIA`): complex leg (with Boresch
  restraints) + solvent leg; the size-bias-free arbiter for the cross-sequence comparison (manuscript §3.9/§3.12).
- **N-methyl RBFE** (parent → N-methyl) for the v2 question — BUT this additionally needs a **CMAP-correct
  N-methyl force field** (committee reviewer C); the current NMET patch is not valid for a quantitative N-methyl ΔΔG.

Cost so far: 5 POC attempts, all fast failures (~$0.05 each ≈ $0.25 total). The converged validation run itself
(~1 GPU-h) and especially binding ABFE (multi-ligand × 2 legs × λ × ns) are genuinely GPU-heavy — scope/estimate
before launching.
