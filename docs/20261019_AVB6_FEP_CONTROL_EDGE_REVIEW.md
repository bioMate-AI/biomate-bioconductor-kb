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

## Preflight outcome (2026-10-19, CPU-only, no spend)
Ran the CPU validation step. No GROMACS/docker locally; used the repo's `mmgbsa_mn` env (ParmEd + OpenMM)
for a grompp-equivalent topology check. Both flagged unknowns are now **RESOLVED**:

- **(a) CaDA `.itp` conversions + angle pairing — VALIDATED.** `fep/validate_cada_itp.py` →
  **`GROMPP_EQUIV_OK`**: (A) a numpy geometry proof confirms the dummy convention +x,−x,+y,−y,+z,−z gives
  TRANS pairs exactly (2,3),(4,5),(6,7) and the twelve CIS pairs matching the `[bonds]` D–D list (adjacent
  D–D = 1.273 Å bonded; opposite = 1.800 Å not bonded); (B) ParmEd parses the exact shipped `.itp` and
  OpenMM builds a valid System — 7 atoms, 18 bonds, 15 angles, angle θ₀ histogram {180°:3, 90°:12}, **net
  charge +2.000**, total mass 54.94 = Mn, center/dummy LJ+charges as sourced. The unit conversions
  (669440 kJ/mol/nm², 2092 kJ/mol/rad², σ=0.169627 nm, ε=53.68 kJ/mol) are confirmed.
  - **One real fix committed:** the dummy `at.num` was `0`, which ParmEd/OpenMM (used elsewhere in this
    repo) misclassify as a massless virtual site and refuse to bond. Set to `1` (cosmetic; GROMACS ignores
    the column); the dummy is a real mass-bearing bonded particle, not a vsite. CaDA params stay sourced.
- **(b) cyclization — RESOLVED structurally.** Both control peptides are **head-to-tail cyclic** (N(res1)–
  C(res9) = 1.30 / 1.32 Å, a covalent amide; zero cysteines → no disulfide). The cyclization is a single
  standard backbone amide bond across the res9→res1 junction, added in `topol.top` with uncharged termini.
  The Y1F+Y7F perturbation is a textbook pmx mutation between two standard residues.

**What literal `gmx grompp` on the FULL assembled complex still needs (container step, not local):** the
CHARMM36m cyclic-peptide topology (pdb2gmx + the one cyclization bond) merged with the validated
`cada_mn.itp` + solvation. This is now standard assembly over **validated** components (the novel/risky
CaDA metal topology is the part that is validated here), and is confirmed by the in-container
`GROMPP_PREFLIGHT` gate in `fep_batch.py` at submit time (it fails fast on CPU before any GPU). pmx
availability in `gromacs-cuda:2024-cu12` is the last open item; the command `pip`-installs it if absent.

## Container preflight progress (2026-10-20, spot CPU, user-run launcher)
Iterating the in-container preflight (`fep/preflight/preflight_in_container.sh`) on `gromacs-cuda:2024-cu12`:
- Stage A: GROMACS 2024.3 OK. Stage B: CHARMM36m (charmm36-jul2022) downloads OK (network fine).
- Stage C: prep moved **offline** (image python has no pip → no gemmi); known-good PDBs staged to S3. OK.
- **Stage D OK — the cyclic peptide validates:** `pdb2gmx` covers the peptide under CHARMM36m; vacuum
  `grompp` OK; and **the head-to-tail cyclization amide bond is accepted by grompp** (`STAGE_Dcyc:OK`,
  CYC_ADDED lastC=149 firstN=1). The FEP-mutated molecule's topology is sound.
- Stage F fixes (this round): the receptor `pdb2gmx` was run with `-ss`, which prompts interactively per
  disulfide (integrin has many); the batch run EOF'd mid-prompt and the piped/pipefail construct emitted no
  marker. Fixed: dropped `-ss` (reduced CYS are valid CHARMM36m residues — correct for an assembly+coverage
  grompp preflight), `< /dev/null` to prevent any hang, explicit `rc=$?`, and a `STAGE_F_ENTER` canary.
- **pmx hybrid — offline, non-gating.** The image python has no pip, so pmx can't install in-container. The
  hybrid needs GROMACS **and** pmx together (`pmx mutate` requires a pdb2gmx-hydrogenated input: it fails
  `N-CA-C-O -> N-CA-C-O-HA-HN` without backbone H). Recipe (run in an env with both, e.g. a gromacs+pmx
  container or conda): `pip install git+https://github.com/deGrootLab/pmx.git@develop`; `pdb2gmx` the peptide
  (adds H); `GMXLIB=<pmx>/data/mutff pmx mutate -ff charmm36m-mut --script "P 1 PHE / P 7 PHE" --keep_resid`;
  `pmx gentop` to fill B-states. This does **not** gate the D/F grompp validations. (pmx develop confirmed
  installable on the author's box; only the GROMACS-hydrogenation step is missing locally.)

## Status
Wired + infra-validated + dry-run clean + **CaDA `.itp` GROMPP-equivalent validated (local, no spend)** +
both flagged unknowns resolved + one fix committed. **Not submitted** (no GPU, no Batch this turn, per
instruction). The remaining full-complex `gmx grompp` is low-risk standard assembly, gated by the
in-container preflight at submit. Ground truth remains the wet-lab assay.
