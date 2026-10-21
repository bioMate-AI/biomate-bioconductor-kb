# αvβ6 FEP control-edge — equilibration acceptance check (BOTH legs pass)

**Date:** 2026-10-21 · Internal. Acceptance verdict for the short equilibration that gates the control-edge
ΔΔG. Both legs (solvent + complex) are now equilibrated; this records the metrics and the verdict. Read-only
analysis of the staged `equil_out/` outputs — no GPU spend.

## Metal model used
**Bonded CaDA Mn at small timestep** (NVT 0.2 fs / NPT 0.5 fs, re-idealized octahedra). The virtual-site
CaDA model (`cada_mn_vsite.itp`) is physically correct but fails numerically (LINCS cannot carry its rigid
K4 constraint cluster) — **deferred** as a cost-optimization for Layer B's `gromacs_pmx_fep`. The ΔΔG is
metal-model-independent given a physically valid model, so the bonded model carries the experiment.

## Acceptance metrics

| Check | Solvent leg | Complex leg | Pass |
|---|---|---|---|
| EM→NVT→NPT completed (npt.gro) | yes | yes (14 MB; `Finished mdrun`) | ✓ |
| LINCS warnings | 0 | 0 | ✓ |
| Fatal errors | 0 | 0 | ✓ |
| Potential (finite, negative) | −75,701 kJ/mol | −2.815×10⁶ kJ/mol | ✓ |
| Temperature | 300.06 K | 299.99 K | ✓ |
| Pressure | 1.76 bar | 0.92 bar | ✓ |
| Density | 1024.5 kg/m³ | 1040.4 kg/m³ | ✓ |

## Complex-leg junction geometry (from npt.gro, the decisive test)
The peptide (residues 1070–1078 in the complex) = `GLY ASP LEU ALA Y2F PRO LYS Y2F ARG` — the two Y2F
hybrids correctly at 1074/1077 (the cyclic-origin rotation that put mutation sites interior).

- **Head-to-tail junction amide C(1078)–N(1070) = 1.344 Å** (target ≈1.33 Å). ✓
- **All 9 backbone amide bonds around the full cycle are 1.33–1.42 Å — 0 out of the 1.25–1.45 Å range.**
  The macrocycle stayed **closed and intact** through NVT+NPT; the head-to-tail junction is as well-behaved
  as the internal amides. ✓
- No LINCS instability, no energy blow-up, temperature/pressure/density equilibrated → peptide geometry is
  bounded (macrocycle did not open, distort, or drift).

The solvent leg (same parameterized junction, standard 2 fs) passed identically earlier — confirming the
junction + the CMAP-omission approximation are dynamically sound independent of the complex environment.

## VERDICT
**JUNCTION HOLDS — the control-edge FEP setup is dynamically validated and scientifically ready.** Both
legs equilibrate cleanly; the head-to-tail cyclic junction (func-5 UB angles, func-9 dihedrals, func-2
impropers, CMAP omitted) is stable and the macrocycle remains closed at the control-edge geometry. The
full per-λ ΔΔG (Trivehexin-mono ↔ avebehexin, Y1F+Y7F) is ready to run on the bonded small-dt model —
pending the user's explicit go. Admissibility of the ΔΔG itself is unchanged: the control↔control ΔΔG must
recover the known small affinity gap before the M7/M11 candidate ladder is admissible.

Production ΔΔG remains GUARDED (`MDRUN_CMD_READY=False`) until that go.
