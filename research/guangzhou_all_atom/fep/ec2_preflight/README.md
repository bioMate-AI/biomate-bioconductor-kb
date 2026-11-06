# FEP control-edge GROMPP preflight — VALIDATED on EC2 (2026-10-23)

Clears the one blocker named in `docs/20261019_AVB6_FEP_CONTROL_EDGE_REVIEW.md` ("topology not locally
validated; no GROMACS on the author's box"). Run on a spot EC2 (c5.2xlarge, Amazon Linux 2023, ~$0.04),
driven over SSM; instance terminated after.

## Result
- `01_install.sh`: GROMACS **2024.5** (conda-forge) + parmed/gemmi/openmm. (pmx build FAILED — needed only
  for the alchemical hybrid, not the preflight.)
- `02_build_protein_preflight.sh`: cif→pdb (chains A,B,P), `pdb2gmx` CHARMM36m (charmm36-jul2022.ff) + tip3p
  → **PDB2GMX_EXIT=0, GROMPP_EXIT=0, em.tpr 4.2 MB** (protein complex topology parses).
- `03_build_metal_preflight.sh`: build 3 CaDA-Mn (center + 6 octahedral dummies @0.9 Å) from the cif Mn
  positions, merge into the protein `.gro`, splice `cada_mn.itp` into `topol.top` (include after FF; `MN2 3`
  in `[molecules]`), solvate (57,665 SOL), `grompp` → **GROMPP_MN_EXIT=0, em_mn.tpr 6.3 MB**.
  → **METAL-AWARE TOPOLOGY VALIDATED: `cada_mn.itp` parses in grompp; the metal-complete solvated system
  builds a valid .tpr.** (Previously validated only by ParmEd/OpenMM; now by actual GROMACS grompp.)

## System
αvβ6 headpiece chains A(595)+B(474) + 9-mer control peptide chain P + 3 Mn (CaDA). Control edge
TRIVEHEXIN `YRGDLAYPK` → AVEBEHEXIN `FRGDLAFPK` = **Y1F+Y7F**, standard L-AAs (no custom ligand FF).

## Remaining (NOT done here)
1. **pmx alchemical hybrid** (Y1F+Y7F dual-topology): pmx failed to pip-build; also do NOT use
   `pdb2gmx -merge all` for the real run — keep chain P separate so pmx can mutate it. Mechanical once pmx
   installs (standard-residue Y→F is routine pmx).
2. **Production FEP** (em→NVT→NPT→12-window HREX, 2 legs, ~2 GPU-days): GPU-spot, GATED on explicit go
   (no-speculative-GPU-spend). Dispatch via `cyclic_llm/fep_batch.py` once hybrid inputs are staged with the
   `FEP_INPUTS_READY` sentinel.
