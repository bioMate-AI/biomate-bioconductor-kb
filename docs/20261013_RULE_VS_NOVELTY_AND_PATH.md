# Rule-based generation vs. novelty — the αvβ6 genus trap, and the path forward

**Date:** 2026-10-13 · Captures the analysis of why rule-constrained generation produces published-similar,
FTO-encumbered αvβ6 monomers, where real differentiation lives, and the prioritized next steps.

## The finding
The acceptance gate forces the scaffold `[FYW]-R-G-D-L-[small]-[FYW]-[dPro]-[NMeLys]` — which **is** the
patented Trivehexin/avebehexin nonapeptide genus. Consequence, confirmed by the gate: **all 8 Round-3 αvβ6
candidates pass H1–H5 AND trip the H8 FTO-genus flag.** A rule that fixes the whole scaffold can only emit
molecules inside the genus. So for αvβ6, **rule-based mechanism-fixing → published-similar, FTO-encumbered
monomers, by construction.**

## Why (and why it's target-specific)
- αvβ6's active pharmacophore is a tight, well-patented motif (RGD→MIDAS in a locked cyclic turn). Every
  mechanism-valid *monomer* is therefore inherently in the genus; the only "free" sequence is P1/P6/P7 — a
  handful of aromatic/small combos, mostly published or one edit away.
- PD-L1 is the opposite: discontinuous interface, no linear motif → much more design freedom but far less
  mechanism certainty. The "rule kills novelty" problem is worst exactly where the rule is tightest.
- **The rule is a good FILTER (mechanism-validity — why we need it) but a poor GENERATOR (novelty).**

## Where differentiation + FTO-clearance actually live (not the monomer sequence)
1. **Scaffold-hop** — loosen the rule from "the whole frame" to "the pharmacophore + geometry." Keep RGD·L and
   the MIDAS-presenting turn + a handle, but free the macrocyclization/scaffold (bicycle, knottin, different
   ring size/linkage, staple, non-nonapeptide). Mechanism preserved, genus diverged.
2. **Non-canonical composition-of-matter at the free positions** — P1/P6/P7 in ncAA space (halo/unnatural
   aromatics — naphthylalanine, 4-F/CF₃-Phe; unusual small residues) that all-canonical published scaffolds
   don't claim, and that can tune αvβ6/αvβ8 selectivity. **This is where a trained generator + the HELM/ncAA
   model beats rule-enumeration** (rules enumerate 20-letter combos in the genus; a model proposes novel
   chemistry in the free slots).
3. **The construct level — the actual moat.** Multivalency/geometry (Trivehexin wins on trimer avidity, not
   monomer novelty), novel linker/spacer, chelator/radionuclide pairing, albumin-binder/PK, and the
   **αvβ6×PD-L1 dual-targeting** option. IP + differentiation live in the labeled construct.
4. **Indication/program** — the cold-GI expansion + the closed DMTA loop.

## Honest bottom line
Do not expect a novel, FTO-clean, *better* αvβ6 **monomer** from rule-constrained generation — the monomer
is a commodity in a patented genus, and rule-enumeration guarantees similarity. Monomer-sequence optimization
has largely run its course. The program's value is the **construct + indication + closed loop**, and the
generation novelty budget should move to **scaffold-hop + ncAA + construct**.

## Now what — prioritized
1. **FTO / patent read on the αvβ6 nonapeptide genus FIRST (decisive, cheap, gating).** Every Round-3 αvβ6
   monomer is in the TRIMT/Notni genus. The spec's H8/P5 "counsel before synthesis" is the *first* step, not
   the last — running docking/synthesis on genus-blocked monomers is wasted. This read decides whether any
   genus monomer is worth pursuing (fast-follower / construct-differentiated) or whether to skip monomers.
2. **If the class is worth pursuing:** stand up the **control-validated docking** (H6/H7 + αvβ8/αvβ3/αvβ5/α5β1
   counter-screen, controls in-batch, validation gate A2) — the real affinity/selectivity gate — on Round-3.
3. **Shift the generator to the novelty space** (regardless of 1/2): scaffold-hop (pharmacophore+geometry
   rule, free scaffold) + ncAA at free positions + construct design (multivalency/linker/chelator; the
   αvβ6×PD-L1 bispecific). This is the only route to a differentiated, FTO-defensible asset.
4. **PD-L1 (free-but-uncertain):** continue the generator (BoltzGen) + docking route; current set is
   confounded-weak; novelty budget is larger here.
