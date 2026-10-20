# αvβ6 FEP control-edge — review-before-spend note

**Date:** 2026-10-19 · Internal. Review note for the FIRST and ONLY FEP edge to run: the A2
control↔control anchor. Follows the protocol in `20261019_AVB6_CADA_AND_FEP_SETUP.md`. Per the
project rule *Review Code Before Testing — No Speculative Deploys*, this note states what the job
runs, the cost, the predicted outcome, and the one blocker that keeps it from a live submit now.

## What the job runs (one edge)
- **Edge:** `CTRL-TRIVEHEXIN (YRGDLAYPK) → CTRL-AVEBEHEXIN (FRGDLAFPK)` — a **double Y→F** relative
  alchemical FEP (remove two aromatic hydroxyls at positions 1 and 7). The RGD pharmacophore, length,
  and backbone are identical; both states are standard L-amino-acid 9-mers natively parameterized in
  CHARMM36m, so **no custom ligand force field is needed** — this is why the control edge is the
  tractable starting point, not a scaffold hop.
- **Inputs:** the two metal-complete, gate-admissible poses `results/poses/CTRL-{TRIVEHEXIN,AVEBEHEXIN}_metal.cif`
  (receptor + 3 Mn + peptide, chain P), the **sourced** CaDA Mn topology `fep/forcefield/cada_mn.itp`
  (Duarte 2014, commit `d08855662`), and the mdp set `fep/mdp/{em,nvt,npt,prod_fep.mdp.template}`.
- **Method:** pmx hybrid (dual-state) topology → em → 200 ps NVT → 500 ps NPT → **12-window HREX**
  production, **5 ns/window**, in **both** legs (complex + unbound peptide); `gmx bar` →
  ΔΔG_bind = ΔG_complex − ΔG_solvent.
- **Dispatch:** `cyclic_llm/fep_batch.py` → Batch queue `biomate-gpu-spot-queue` (ENABLED),
  job-def `biomate-gromacs-cu12-gpu` (ACTIVE, `gromacs-cuda:2024-cu12`, GPU=1). **Spot only.**

## Cost
- ~**1 GPU-day per leg** for a converged 12×5 ns HREX edge → **~2 GPU-days for the two legs**.
- Spot g5/g4 GPU ≈ $0.30–1.20/GPU-hr → **~$15–60** for the full control edge, self-terminating.
- No on-demand. If spot is unavailable the job sits RUNNABLE and fires on capacity — correct, not a failure.

## Predicted outcome / admissibility criterion
The control↔control ΔΔG **must recover the small experimental affinity gap** between two known αvβ6
binders (Trivehexin arm vs avebehexin differ only by two Tyr→Phe; the expected |ΔΔG| is **small, a few
tenths to ~1 kcal/mol**, not a large number). **If the edge returns a small, converged ΔΔG with tight
replicate error → the setup is admissible** and the candidate ladder (M7↔control, M11↔control) may run.
**If it returns a large or non-converged ΔΔG → the metal-bridged FEP setup itself is not yet trustworthy**
and no candidate ranking is reported. This is the same control-gated discipline that (correctly) ruled the
single-point MM-GBSA inadmissible.

## The one blocker — why this is NOT submitted this turn (and the gate is NOT spot capacity)
The seam is **wired and infra-validated** (dry-run clean: queue ENABLED, job-def ACTIVE, both inputs +
`cada_mn.itp` present, payload emitted). What is **not** done is **local topology validation**: there is
no GROMACS on the author's box, so the pmx hybrid topology + the CaDA-Mn `.itp` have **not been parsed by
`gmx grompp`** here. Two specific unknowns remain:
1. **CaDA `.itp` unit conversions + octahedral angle pairing.** `cada_mn.itp` carries the Duarte values
   with every unit conversion shown inline for audit, but the trans/cis (180°/90°) angle assignment is a
   placeholder that must be reconciled against the *actual generated Mn-dummy coordinates*, and the
   kcal→kJ / AMBER-½k conversions must be confirmed by grompp.
2. **pmx availability + cyclization.** `biomate-gromacs-cuda:2024-cu12` may not ship `pmx`; and if the
   control peptides are cyclic, the cyclization bond must be added to the hybrid topology.

Per *No Speculative Deploys* (“Predict the outcome. If you can't predict it, you haven't reviewed
enough.”), I **cannot predict** that grompp parses the topology, so I do **not** spend the GPU-day on a
blind submit. The container command is written to **fail fast and cheap**: it runs pmx + `gmx grompp` on
CPU and **exits non-zero before any `mdrun`** if the topology is broken (`GROMPP_PREFLIGHT_FAIL` / `PMX_MISSING`),
so a bad topology costs seconds, not a GPU-day — but that is a safety net, not a substitute for the local
validation step.

## To clear the blocker → live submit (bounded, one edge)
1. In the `gromacs-cuda:2024-cu12` container (or a CPU box with GROMACS): build the pmx hybrid topology
   for Y1F+Y7F, assemble `topol.top` including `cada_mn.itp`, solvate+ionize, and run the **grompp
   preflight** until `GROMPP_PREFLIGHT_OK`. Fix the angle pairing / unit conversions / cyclization there.
2. Stage the validated inputs to the job's `in/` S3 prefix.
3. `python cyclic_llm/fep_batch.py --submit` → one spot GPU job; record the real job id + state.
4. Run **only** the control edge; report ΔΔG + convergence/replicate error honestly. Candidate-ladder
   edges do **not** run until the control edge is recovered.

## Status
Wired + infra-validated + dry-run clean. **Not submitted.** Gate = local topology validation (above),
**not** spot capacity. Ground truth remains the wet-lab assay.
