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

## Energy half — RAN (2026-10-19); controls DIVERGE → INADMISSIBLE with a non-bonded Mn model
`mmgbsa_metal_local.py` (local CPU, `mmgbsa_mn` env) ran all 4 poses with the **verified** Li-Merz 12-6 CM
Mn²⁺ param (Rmin/2 = **1.407 Å**, ε = **0.0168671 kcal/mol**; Li,Roberts,Chakravorty,Merz *JCTC* 2013, 9, 2733,
transcribed from AmberTools `frcmod.ions234lm_126_tip3p`). All 3 Mn retained on the receptor side; all peptides
ring-closed. 8 Å pocket, GBn2/CHARMM36m minimized single-point.

| pose | ΔG (kcal/mol) | — |
|---|---|---|
| CTRL-TRIVEHEXIN (known binder) | **−7.2** | |
| CTRL-AVEBEHEXIN (known binder) | **−122.2** | |
| AVB6-SH-M7-01 | −113.6 | |
| AVB6-SH-M11-01 | −123.9 | |

**A2 control-anchoring FAILS → scores INADMISSIBLE.** The two comparable known αvβ6 binders differ by
**115 kcal/mol** — physically impossible for real binding. The ΔG is dominated by the artifactual,
distance-sensitive **Asp⁻···Mn²⁺ electrostatic** (a fixed-charge +2 metal at cofold-placed, sometimes sub-Å,
separations), not recoverable affinity — the documented failure mode of non-bonded metal MM-GBSA. **No ranking
is reported.** The geometric site-fidelity gate (above) remains the defensible metal-aware result. To make the
energy step admissible, the Mn needs a **12-6-4 LJ** (Li & Merz, *JCTC* 2014/2015) or a **bonded / cationic-dummy
(CaDA)** model, and the controls must cluster before any candidate ΔG is trusted.

(`results/avb6_metal_mmgbsa_dG.json` carries the raw ΔG + the inadmissible verdict.)

### Code (built + run): the three changes, all in `mmgbsa_metal_local.py`
The local env (`conda env mmgbsa_mn`: openmm 8.5.2 + parmed + psfgen + gemmi) is built; **CPU, no GPU/cloud**:
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

**Actual outcome:** the prediction (controls cluster strongly-negative) was **wrong** — the fixed-charge
non-bonded Mn²⁺ made the controls diverge by 115 kcal/mol (see table). This is itself the useful finding: a
simple non-bonded +2 metal is **not** adequate for an admissible αvβ6 energy ranking.

## Precise next step
The **defensible metal-aware result today is the geometric gate** (controls + both scaffold-hops engage the
MIDAS Mn via Asp; M7 1.96 Å < M11 2.34 Å). For an admissible **energy** ranking, re-parameterize Mn with the
**12-6-4 LJ** set (Li, Song, Merz, *JCTC* 2014/2015 — the polarization term tames the +2 electrostatics) or a
bonded/CaDA model, re-run `mmgbsa_metal_local.py`, and require the controls to **cluster** (A2) before reporting
any scaffold-hop ΔG. Do **not** advance to a CRO order on these numbers. FEP confirmation of any finalist.
