# αvβ6 metal-aware MM-GBSA — method-dev: Mn retention + control-anchoring (status)

**Date:** 2026-10-19 · Internal. Advances the "Next: metal-aware MM-GBSA (retain + parameterize Mn)"
step from `20261014_CYCLIC_PEPTIDE_PROGRAM_MASTER.md §4`. Scope: the cyclic-drug thread (αvβ6 radioligand
scaffold-hops). Two halves — the **structural/geometric** half is built, validated, and MEASURED here; the
**energy** half is specified + launch-ready, blocked only on one sourced parameter.

---

## Why metal-aware at all
Integrin αvβ6 RGD binding is **MIDAS-metal-mediated**: the ligand Asp carboxylate completes the coordination
of the β6 MIDAS Mn²⁺. The prior MM-GBSA dropped the metal (`split_design()` kept only
`gemmi…is_amino_acid()` residues), so the bridging Asp→Mn interaction vanished and ΔG came out
weak/positive (e.g. metal-free EN-04 +6.77 kcal/mol) — structurally unable to score the real binding mode.

## What was built + MEASURED this session (structural half — real)
`research/guangzhou_all_atom/metal_mmgbsa_prep.py` (dependency-free; runs now):
- **Receptor-side Mn split.** Parses a metal-aware cofold pose (Boltz-2 with 3 Mn CCD ligands), splits
  receptor(+Mn) / peptide(chain P). The Mn rides with the **receptor** so
  `ΔG = E_complex − E_receptor(+Mn) − E_ligand` captures the peptide-Asp→MIDAS-Mn bridge (present in the
  complex, absent in each monomer).
- **Dry-run assertion:** all 3 Mn retained on the receptor side for every pose (passes).
- **A2 control-anchoring geometric gate:** known binders must place their RGD Asp carboxylate in direct
  MIDAS-Mn coordination, else the metal-aware setup is inadmissible.

**Result (`results/avb6_metal_mmgbsa_gate.json`, `results/avb6_metal_coordination_geom.json`):**

| pose | coord res | Asp O–Mn (Å) | inner-sphere | engages |
|---|---|---|---|---|
| CTRL-TRIVEHEXIN (known binder) | ASP | 0.81 | ✓ | ✓ |
| CTRL-AVEBEHEXIN (known binder) | ASP | 1.91 | ✓ | ✓ |
| AVB6-SH-M7-01 (scaffold-hop) | ASP | 1.96 | ✓ | ✓ |
| AVB6-SH-M11-01 (scaffold-hop) | ASP | 2.34 | ✓ | ✓ |

**Verdict: ADMISSIBLE.** Both controls recover the known RGD-Asp→MIDAS-Mn coordination — the metal-aware
cofold setup is validated. Both scaffold-hops **engage the MIDAS Mn** via their Asp (M7 1.96 Å tighter than
M11 2.34 Å) — the metal-mediated engagement the metal-free pipeline structurally could not see.

**Honest limits:** coordination distances are **cofold-approximate** (Boltz places the metal with no explicit
vdW repulsion — Trivehexin's 0.81 Å is below physical inner-sphere and is a model artifact). This is a
**RELATIVE/qualitative site-fidelity** verdict (does the ligand engage the metal site), **never an affinity**.
Ground truth remains the wet-lab binding/competition assay.

## Energy half — launch-ready, blocked on ONE sourced parameter
The OpenMM GBn2 MM-GBSA energy step (per `peptide_mmgbsa_pocket_run.sh`) needs three code changes, all
specified; the local env (`conda env mmgbsa_mn`: openmm 8.5.2 + parmed + psfgen + gemmi) is built, so it is a
**local CPU job (~minutes for 4 poses), no GPU/cloud**:
1. **split_design** → use `metal_mmgbsa_prep.split_sides()`: write the 3 Mn as a psfgen `ION` segment
   (resname `MN2`, atom `MN`, `first='none' last='none'`) on the receptor side; keep them in the
   `rec_idx` (segid≠PEP) slice so E_receptor includes the metal.
2. **Mn²⁺ parameter** — a custom `mn_charmm_param.str` (RESI MN2 charge +2; NONBONDED MN). Use the
   **Li & Merz 12-6 TIP3P** divalent set (Li, Roberts, Chakravorty, Merz, *JCTC* 2013, 9, 2733) — the
   validated non-bonded Mn²⁺ LJ (Rmin/2, ε), loaded via `CharmmParameterSet(RTF, PRM, 'mn_charmm_param.str')`.
   This is the one input not memorizable and not fetchable this session; **do not fabricate the LJ values.**
   Approximate (non-bonded, fixed-charge) — a bonded / 12-6-4 / cationic-dummy model would be more accurate.
3. **Control gate on ΔG** — score CTRL-TRIVEHEXIN + CTRL-AVEBEHEXIN every batch; emit the scaffold-hop
   ΔG ranking **only if** controls recover strongly-negative, correctly-ordered ΔG (A2). A `refuse-on-stub`
   guard must abort if `mn_charmm_param.str` is absent/placeholder — so no number is ever produced with
   unvalidated Mn params.

**Predicted outcome (energy step, once param supplied):** controls flip from the metal-free weak/positive
ΔG to strongly negative and correctly ordered (gate passes); M7 and M11 both score negative with M7 ≈ or
slightly stronger than M11 (consistent with the tighter coordination), giving the first physically-valid
within-αvβ6 ΔG ranking of the scaffold-hops. FEP confirmation of finalists still required.

## Precise next step
Supply `mn_charmm_param.str` (Li-Merz 12-6 Mn²⁺), then:
`conda run -n mmgbsa_mn python mmgbsa_metal_local.py` (energy runner per the 3 changes above) → controls-gated
ΔG ranking of `avb6_scaffoldhop_r1.json` / `avb6_monocyclic_scaffoldhop.json`. Then per-scaffold FTO + CRO.
