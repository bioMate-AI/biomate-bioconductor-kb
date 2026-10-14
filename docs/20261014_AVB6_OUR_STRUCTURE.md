# αvβ6 — our own structure (metal-complete receptor) + plan

**Date:** 2026-10-14 · The αvβ6 affinity work was blocked because the Boltz cofold dropped the catalytic MIDAS
metal (RGD binding is metal-mediated). Fix: establish our OWN controlled, metal-complete αvβ6 structure as the
canonical docking target, instead of a metal-free fold or a borrowed raw crystal.

## What we built (v1) — `results/receptors/avb6_ourstructure_v1.cif`
Curated from PDB 9XMM (Notni et al.): αV+β6 headpiece (10,427 protein atoms) + the **full metal cluster** —
MIDAS Mn (coordinated bidentate by the RGD Asp + β6 Ser, confirmed), ADMIDAS + SyMBS Mn, and 4 Ca. Glycans
(NAG/BMA/MAN), the co-crystal ligand (CHG), and water removed. This is a controlled, versioned receptor we own
and can prep/iterate — not the metal-free fold that produced the invalid (positive) ΔG.

## The three senses of "our own structure" (honest)
1. **Curated metal-complete receptor (DONE, v1)** — derived from 9XMM, metals retained. Unblocks metal-aware
   computation now. Derived, not independent.
2. **Our own PREDICTED model** — de novo fold of the αV+β6 headpiece WITH the Mn/Ca as ligand entities
   (Boltz-2/AF3 ion entities), optionally an ensemble (apo + RGD-bound) for induced-fit. Independent of the one
   crystal; a prediction to validate against the controls.
3. **Our own EXPERIMENTAL co-structure** — cryo-EM/crystallography of αvβ6 bound to OUR scaffold-hop lead. This
   is the real program asset: enables structure-based design we own and supports IP. Wet-lab → SDL / collaborator
   route (see self-driving-lab plan), not computable here.

## Next (compute, now unblocked by v1)
- **Metal-aware docking** of the scaffold-hop leads (bicyclic SH-BCY-*) into v1 with the MIDAS metal present,
  holding receptor+metals fixed, and **validate on the controls** (Trivehexin/avebehexin must show RGD-Asp→MIDAS
  coordination and rank strong, A2). Only then are αvβ6 affinity/selectivity numbers admissible.
- Counter-integrin selectivity (αvβ8/αvβ3/αvβ5) via the analogous metal-complete receptors.

## Status
v1 receptor committed. Metal-aware docking protocol is the next build; experimental co-structure is the program
asset to pursue via the lab route.
