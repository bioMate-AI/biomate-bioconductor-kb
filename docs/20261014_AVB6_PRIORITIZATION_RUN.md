# αvβ6 prioritization run — cap bug FIXED, but MM-GBSA is invalid for this target (no MIDAS metal)

**Date:** 2026-10-14 · Applied the PD-L1 pipeline to αvβ6 (per user request). Two findings; the important one
is that the method does not transfer.

## 1. The deferred MM-GBSA cap bug is FIXED (verified)
Root cause (diagnosed from the log): pocket-truncated receptor fragments used ACE/CT3 caps that ADD terminal
atoms psfgen must guess; on ragged pocket cuts the guess failed for some poses ("bad angle O C NT") → PSF vs
written-PDB atom-count divergence → `setPositions` throws → the deterministic 5/10. Fix: `first/last='none'`
(no terminal patch, no guessable atoms). **Verified:** every αvβ6 design that ran scored cleanly (no
setPositions failures), vs 5/10 before. The fix is real and committed.

## 2. But the αvβ6 MM-GBSA ΔG is NOT trustworthy — two reasons
**(a) Physics: the MIDAS metal is absent.** αvβ6 is an integrin; RGD binding is *metal-mediated* — the Asp
carboxylate coordinates the MIDAS divalent cation (Mg²⁺/Mn²⁺). The Boltz cofold used protein-only receptor
chains, so the complex contains **no metal ion** (verified: zero HETATM in the complex CIF). Without the metal,
the dominant RGD–integrin interaction is missing, so the ΔG is unphysical — which is exactly what the numbers
show: weak and even **positive** values (R3-02 +5.4, R3-04 +0.2), nothing like a sub-nM binder. The scoring
that works for PD-L1 (a pure hydrophobic PPI, no metal) does NOT transfer to αvβ6 without adding the MIDAS ion.
**(b) Incomplete + no control anchor.** The run scored 7/10 before the instance ended; R3-08 and BOTH controls
(Trivehexin, avebehexin) did not score — so there is no A2 validation. Even complete, (a) would still void it.

Raw (for the record only, NOT a ranking): R3-05 −26.5, R3-03 −13.6, R3-07 −10.4, R3-01 −5.3, R3-06 −1.4,
R3-04 +0.2, R3-02 +5.4. Do not use.

## 3. Honest conclusion for αvβ6
- I will NOT produce an αvβ6 order from these numbers — they are physically invalid (no metal) and unanchored.
- Doing αvβ6 affinity *properly* needs a pipeline extension: place the MIDAS Mg²⁺/Mn²⁺ (and typically the ADMIDAS/
  SyMBS ions) at the integrin site — e.g., by superposing a reference αvβ6·RGD structure — before MM-GBSA, or use
  a metal-aware method. That is real additional work.
- Strategically it changes nothing orderable: every Round-3 αvβ6 monomer is in the patented Trivehexin/avebehexin
  genus (H8/FTO fires on all). The αvβ6 decision is the FTO read + the construct, not a monomer ΔG ranking.

## Status
Cofold `cofold-v2-9xmm-20261014T095643Z` (10/10 folded). MM-GBSA `mmgbsa-pool-9xmm-s0of1-20261014T105902Z`
(cap-fix verified; metal-omission makes ΔG invalid). `results/avb6_r3_mmgbsa.json` (7 designs, do-not-use).
