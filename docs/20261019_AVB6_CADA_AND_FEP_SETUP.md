# αvβ6 metal model — CaDA params (sourced) + why single-point MM-GBSA stays inadmissible → FEP/TI setup

**Date:** 2026-10-19 · Internal. The CaDA track for a trustworthy αvβ6 ranking. The fixed-charge single-point
MM-GBSA was inadmissible (controls diverged 115 kcal/mol; `20261019_AVB6_METAL_MMGBSA_METHODDEV.md`). This note:
(1) the **sourced** cationic-dummy-atom (CaDA) model for the MIDAS Mn²⁺ — no fabricated params; (2) the honest
reason a CaDA *single-point MM-GBSA* is still not the admissible fix; (3) the **FEP/TI protocol** (design only —
no GPU run this turn).

## 1. CaDA model — SOURCED (Duarte, Bauer, Barrozo, Amrein, Purg, Åqvist, Kamerlin, *J. Phys. Chem. B* 2014,
118, 4351 — "Force Field Independent Metal Parameters Using a Nonbonded Dummy Model"). Values verbatim from
Table 1 (Mn²⁺, octahedral), fit for TIP3P/SPC.

**Model:** central Mn surrounded by 6 massless-vdW dummy atoms at octahedral vertices; each dummy carries +δ,
the center carries n−6δ (net +2). Charge delocalization + a rigid octahedron pin the coordination geometry,
which the point-charge fixed-metal model could not.

| term | value (Duarte 2014) |
|---|---|
| M–D bond | Kb = 800.0 kcal·mol⁻¹·Å⁻², r0 = **0.900 Å** |
| Di–Dj≠i bond | Kb = 800.0, r0 = **1.273 Å** (= 0.9·√2; rigidifies the octahedron) |
| angles Di-M-Di / Di-M-Dj / M-Di-Dj / Di-Dj-Di / Di-Dj-Dk | Kθ = 250.0 kcal·mol⁻¹·rad⁻², θ0 = 180° / 90° / 45° / 90° / 60° |
| Mn center | mass 36.94, charge **−1.00**, LJ Aᵢ = 171.00, Bᵢ = 35.00 |
| dummy D | mass 3.00 (×6 → 54.94 total = Mn), charge **+0.50**, LJ Aᵢ = 0.05, Bᵢ = 0.00 |

Potential (paper eq 1): `U = qᵢqⱼ/4πε₀r + Aᵢⱼ/r¹² − Bᵢⱼ/r⁶`, with geometric combining `Aᵢⱼ=AᵢAⱼ, Bᵢⱼ=BᵢBⱼ`.

**CHARMM/OpenMM conversion (algebra from the paper's own form, not fabricated):** for the self term
A=Aᵢ², B=Bᵢ², V=A/r¹²−B/r⁶ ⇒ Rmin=(2A/B)^(1/6), ε=B²/4A. Mn center → **Rmin/2 = 0.952 Å, ε = 12.83 kcal/mol**
(a small-radius deep-well center — the dummy-model convention; the +0.5 dummies, not the center, do the
coordinating). Dummy → Bᵢ=0 ⇒ ε = 0 (point charge, negligible vdW), charge +0.50.
*Caveat:* Duarte uses geometric LJ combining; CHARMM uses Lorentz-Berthelot — a minor approximation on the
center–ligand vdW (the center LJ is mainly a repulsive wall; coordination is dummy-charge-driven).

## 2. Why a CaDA *single-point MM-GBSA* is still not the admissible fix (honest)
- **The CaDA model is parameterized and validated for MD + FEP** — Duarte fit it to reproduce FEP solvation free
  energies and MD radial-distribution M–O distances. Its validity for a **single-point, minimized MM-GBSA** of a
  bridged protein–peptide interface is **not established**; geometry-pinning would likely cluster the controls,
  but the resulting ΔG would be an off-label number, not a validated affinity — reporting a ranking from it would
  violate the "admissible, control-gated" bar.
- **Implementation note:** a faithful CHARMM build needs the octahedral angle set, where Di-M-Di (180°) and
  Di-M-Dj (90°) are the *same* atom-type triple (DUM-Mn-DUM) with two equilibria — the standard-FF degeneracy
  that production CaDA tooling (the Q program; AMBER MCPB-style builds) handles with per-pair typing, not a
  hand-rolled single-turn psfgen residue.
- **Conclusion:** the sourced CaDA model belongs in **FEP/TI**, its validated use — which is also the
  methodologically correct way to get a trustworthy metal-bridged binding ΔG. **αvβ6 ranking remains INADMISSIBLE
  under single-point MM-GBSA; no ranking is reported.** The geometric site-fidelity gate
  (`metal_mmgbsa_prep.py`: controls + M7/M11 engage the MIDAS Mn) stays the defensible MM-level result.

## 3. FEP/TI protocol (DESIGN ONLY — no GPU run this turn; spot + review-note + go-ahead gated)
**Goal:** relative binding free energy ΔΔG of the αvβ6 scaffold-hops vs the known-binder controls, with the CaDA
Mn — the admissible ranking the single-point method cannot give.
- **System:** metal-complete αvβ6 headpiece (`avb6_ourstructure_v1.cif`) + the CaDA MIDAS Mn (§1) + cyclic
  peptide, explicit TIP3P (the CaDA fit water), 0.15 M ions, ~90 Å box; CHARMM36m protein + the CaDA Mn params.
- **Method:** relative alchemical FEP (or TI) — mutate peptide A → peptide B along a λ-schedule (dual-topology
  for the variable positions); run in **both** legs (complex + solvent) for ΔΔG_bind = ΔG_complex − ΔG_solvent.
  Engine: GROMACS (`biomate-gromacs-cu12-gpu` Batch job-def exists) or OpenMM/Perses; replica exchange over λ
  (HREX), ~12–24 windows, ≥5 ns/window, 3 replicas for error bars.
- **A2 control-anchoring:** include the **control↔control** edge (Trivehexin ↔ avebehexin) — its ΔΔG must match
  the small experimental affinity gap of two known binders; only if that edge is recovered is the candidate
  ladder admissible. Candidates enter via edges to a control (M7 ↔ avebehexin, M11 ↔ avebehexin).
- **Cost / gating:** spot GPU, self-terminating; ~1 GPU-day per edge for a converged relative FEP. This is a
  **reviewed, budgeted** run — **not fired this turn**; needs a fresh review note + explicit go-ahead. Routed
  through the Batch seam (`cyclic_llm/physics_batch.py`, extended to the GROMACS FEP job-def).
- **Deliverable of the run (when approved):** control-anchored ΔΔG ladder of M7/M11 vs controls — the first
  admissible αvβ6 ranking — with honest convergence/error reporting; ground truth remains the wet-lab assay.

## Sources
Duarte et al., *J. Phys. Chem. B* 2014, 118, 4351 (CaDA params, via diva-portal FULLTEXT postprint); Åqvist &
Warshel 1990 (original octahedral dummy); prior status `20261019_AVB6_METAL_MMGBSA_METHODDEV.md`.
