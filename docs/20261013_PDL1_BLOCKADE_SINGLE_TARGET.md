# PD-L1 blockade macrocycle — single-target program (the plan)

**Date:** 2026-10-13 · Living doc. Direction set by user: **PD-L1 is pursued as a blockade (PD-1/PD-L1
PPI-block) agent, single-target — not a radioligand and not a bispecific arm.** The radioligand-vs-blockade
question is **decided = blockade**; this doc supports that plan and lays out how to execute it well. No
multi-target / multivalent / bispecific constructs.

## Why the blockade framing is the right call (it removes the objections, not defers them)
The two liabilities I'd raised against PD-L1 were specific to the **radioligand** modality and **disappear** for
a blocker:
1. **Expression sink (A6) — gone as a disqualifier.** For a radioligand, broad PD-L1 expression on normal/
   immune cells means high background + target-mediated clearance. For a **blocker**, broad expression is
   expected and fine — the metric is PD-1/PD-L1 occupancy at the tumor, not signal-to-background. The sink is
   a PK/dose problem, not a modality-killer.
2. **Mandatory cationic chelator handle — gone.** A blocker carries **no radiometal**, so there is **no
   required NMe-Lys/DOTA handle** and no obligate renal-charge liability. That removes the single most
   constraining design rule and **opens real sequence/novelty freedom** — the opposite of the αvβ6 genus trap.

So blockade is not a fallback; it is the modality where PD-L1 is genuinely tractable and where there is room to
design something differentiated.

## Mechanism / design target
- **Block the PD-1-binding face of PD-L1** (the front β-sheet / CC'FG face engaged by PD-1). Macrocyclic
  peptides are a validated chemotype here (BMS macrocyclic-peptide PD-L1 inhibitor lineage).
- **Readout is competition, not retention:** PD-1/PD-L1 binding inhibition (HTRF/AlphaLISA/SPR) + a cell-based
  PD-1/PD-L1 blockade reporter (e.g., Jurkat-NFAT / PD-1-PD-L1 bioassay). No chelator, no dosimetry.
- **Chemotype:** amphipathic macrocycle covering a discontinuous interface — structure/docking-gated (there is
  no linear motif), which is exactly why the design freedom is larger than αvβ6's motif-locked pocket.

## Validation plan (control-anchored, same rigor bar as αvβ6 A2)
1. **Published control blocker in-batch.** A BMS macrocyclic-peptide PD-L1 inhibitor (e.g., BMS-986189 class).
   **Citation-integrity flag:** exact sequence + reported IC50/Kd must be **sourced and verified from the
   primary patent/literature before synthesis — do NOT fabricate.** No valid public control → no admissible
   assay (same bar we held αvβ6 to).
2. **Structure-gated scoring on candidates** (K-01/02/05 and new designs): dock to the PD-1-interface of a
   PD-L1 crystal structure, MM-GBSA on the labeled-free peptide, then the competition assay. P1 provenance +
   P4 selectivity apply.
3. **Selectivity:** PD-L1 vs **PD-L2** (both bind PD-1) — decide pan vs PD-L1-selective as an explicit design
   choice, not an afterthought.
4. **Developability:** proteolytic/plasma stability, permeability (blocker PK is the real challenge for a
   peptide vs an antibody), aggregation — the standard macrocycle liability panel.

## Advantages / honest tradeoffs vs an anti-PD-L1 antibody
- **For:** smaller, cheaper, potential tissue penetration, no Fc effector baggage, tunable half-life, oral/SC
  potential.
- **Against:** shorter half-life / PK is the central hurdle for a peptide blocker; antibodies set a high
  efficacy bar in the clinic. Differentiation must be a real niche (penetration, combination, route), not
  "a peptide version of a mAb."

## Immediate next steps (no deferral — these start now on request)
1. Source + verify a published PD-L1 macrocycle control (primary literature), establish the admissible assay.
2. Provenance-check K-01/02/05; dock survivors to the PD-1 interface; score.
3. Because the handle constraint is gone, run **unconstrained macrocycle generation** against the PD-1-interface
   (this is where the design freedom — and the novelty you wanted — actually exists for this target).

## Combination strategy (decided 2026-10-13): two agents, regimen-level — NOT one molecule
αvβ6 and PD-L1 are pursued as **two independent single-target molecules** (αvβ6 radioligand; PD-L1 blocker)
and, if used together, **combined at the regimen level** as a radio-immunotherapy: αvβ6-targeted RLT drives
immunogenic cell death + antigen release (warms the cold PDAC/GI microenvironment) and the PD-L1 blocker
releases the checkpoint brake. This realizes the cold→hot thesis with two coherent single-target drugs instead
of a modality-incoherent fused bispecific (a radiometal-delivery warhead and a PPI blocker on one macrocycle
would fight each other). No fused molecule; the combination is clinical/regimen, not molecular design.

## Scope boundaries
- Single-target PD-L1 blockade only. No αvβ6×PD-L1 bispecific, no multivalent dual-target construct
  (`20261013_CONSTRUCT_DESIGN_AVB6_PDL1.md` remains HALTED).
- αvβ6 remains its own separate single-target program (unchanged by this doc).
- Any αvβ6+PD-L1 pairing is a **combination of two separate agents**, handled as a regimen/trial design, not a build task.
