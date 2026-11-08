# Detailed design — learnings from the symbolic-neural (SNG) approach

**Date:** 2026-10-15 · Concrete lessons from Symbolic Neural Generation (SNG, `arXiv:2510.23379`) and the detailed
design incorporating them. Companion to `20261015_LOOP_BUILD_SPEC_PHASE0_AND_PHASE1.md` and
`20261015_OWN_LLM_OPTIMIZATION_DIRECTION.md`.

## 1. What SNG does (precise)
Inductive Logic Programming (ILP) induces symbolic specifications from a very small set of actives — sometimes
one. Each spec (a) constrains the conditional information fed to a neural generator and (b) acts as a rejection
filter on generated instances. Output is a pair (H, X): H = symbolic rules, X = molecules that provably satisfy
them. Useful on poorly-understood targets (few actives); binding "on par with clinical candidates"; experts reuse
the induced rules as preliminary filters.

## 2. Five transferable learnings (each mapped to our design)
**L1 — Learn the rule from few actives; don't hand-code it.** Our `acceptance_gate` (RGD.L + D-Pro + aromatic
flanks + single handle) is a hand-written symbolic hypothesis. SNG induces that hypothesis from the handful of
known binders. Benefits: scales to a new target without hand-crafting; ILP is built for tiny data (1-few examples)
= exactly the peptide regime, sidestepping no-tiny-dataset for rule induction; can surface constraints we missed.

**L2 — Rules do double duty: condition the generator AND reject violators.** We already reject (acceptance_gate).
Add the missing half: feed the induced spec as generation conditioning so candidates satisfy it by construction,
then reject residuals. Constrain + reject, not reject-only.

**L3 — Emit the RULE as a first-class artifact (the H in (H,X)).** Output the explicit design specification per
round, not only the molecules. It is interpretable, auditable (useful for FTO/regulatory), and reusable. We do
this implicitly via the gate; make the rule an explicit, versioned output.

**L4 — The few-active regime is our regime (cold-start).** New targets have 1-few known binders. ILP few-shot
induction fits this, unlike data-hungry deep generators. For a new target: induce the spec from its few actives,
constrain the generator immediately — no waiting for a big dataset.

**L5 — Correctness-by-construction as the trust layer.** Generated instances provably satisfy the symbolic spec,
so the expensive verifier only scores rule-satisfying candidates (efficiency) and the output carries a correctness
guarantee (trust). Matches our honest/verifiable ethos.

## 3. Detailed design — the symbolic layer (new/upgraded)
### 3.1 Candidate as logical facts
Represent each candidate as predicates over its HELM: `has_motif(X,rgdl)`, `position(X,p1,aromatic)`,
`has_turn(X,dpro)`, `handle_count(X,1)`, `ring_size(X,9)`, `flank(X,p1,phe)`, `net_charge(X,n)`, `topology(X,headtotail)`,
`in_claim(X,ca2998968)`, `ncaa(X,p7,nal2)`... Background knowledge: residue properties (aromatic/small/charged),
motif definitions, mechanism tags (metal cofactor), patent-claim predicates.

### 3.2 Rule induction (the SNG/ILP step — new)
- Positives = known actives (Trivehexin, avebehexin for avb6; 5O45 macrocycle for PD-L1); negatives = known
  non-binders / decoys / counter-target-preferring (e.g. the G2 pan-binders).
- Induce hypothesis H, e.g. `binder(X) :- has_motif(X,rgdl), has_turn(X,dpro), flank_aromatic(X,p1),
  flank_aromatic(X,p7), handle_count(X,1)` — which is our acceptance_gate, but LEARNED. Re-induce per target.
- Engine: an ILP system (Popper / Aleph / Metagol). Build = the peptide predicate representation + the example sets.

### 3.3 Rule types (richer than SNG; our extension)
Induce/encode four constraint families as symbolic specs, all dual-use (condition + reject):
- **pharmacophore** (induced from actives — SNG core);
- **FTO/claim-scope** (from the patent KB: `in_claim`, dissimilarity) — generate OUTSIDE the estate by construction;
- **developability** (hydrophobicity/liability predicates);
- **mechanism** (metal cofactor / epitope type → configures the scorer).

## 4. How it plugs into the loop + own-LLM
- **Generator (own peptide LLM):** conditioned on the induced spec H (L2) — proposes in the free positions only;
  the hard scaffold is satisfied by construction.
- **Rejection + verifier:** residual violators rejected (L5); survivors scored by the mechanism-matched verifier
  stack (binding/selectivity/developability/FTO/geometry, control-anchored).
- **Output:** (H, ranked X) — rules + gated candidates + provenance (L3).
- **Co-evolution:** the loop's scored/assayed data both (a) grows the ILP example sets (better rules) and (b)
  trains the own generator (SFT->RLVR). Symbolic and neural improve from the same data factory.

## 5. The concrete upgrade to what we built
`acceptance_gate.py` (hand-coded) -> an *induced* spec per target: same structure, but learned from the few
actives via ILP, re-inducible for any new target, and emitted as a first-class rule artifact. This is the single
highest-value SNG-derived change — it removes the per-target hand-crafting bottleneck and gives correctness-by-
construction generation.

## 6. Honest caveats
- SNG is small-molecule; the ILP induction + constrain-generate-reject pattern transfers, the representation is
  ours (HELM predicates).
- ILP engine + peptide predicate layer is a real build (not huge: Popper/Aleph are mature).
- Few-active induction can over/under-fit with 1-2 examples; use it to PROPOSE the spec, then let the verifier +
  more data refine it (induced rule is a prior, not final truth).
- No SNG code released; we implement the pattern.

## Summary
Adopt four SNG learnings: (L1) INDUCE the design rule from the few known actives instead of hand-coding it;
(L2) use it to BOTH condition the generator and reject violators; (L3) emit the rule as a first-class artifact;
(L4/L5) it fits our few-active cold-start and gives correctness-by-construction. Concretely: turn the hand-coded
acceptance_gate into an ILP-induced, per-target spec that conditions the own peptide generator and feeds the
verifier loop. Extend beyond SNG by inducing/encoding FTO, developability, and mechanism as symbolic specs too.
Source: https://arxiv.org/abs/2510.23379
