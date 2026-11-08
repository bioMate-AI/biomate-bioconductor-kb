# Build plan — Target KB + ILP-style rule induction (Phase 0, first build)

**Date:** 2026-10-15 · Concrete first build of the lead-generation system upgrade: a structured Target KB and an
induced design-rule (the SNG L1 learning — learn the spec from the few actives instead of hand-coding
`acceptance_gate`). Design: `20261015_DETAILED_DESIGN_SYMBOLIC_NEURAL_LEARNINGS.md`.

## Goal
Replace the hand-coded `acceptance_gate` with a rule **induced** from each target's few known actives, proving:
(a) the rule reproduces our hand-coded gate from data; (b) it generalizes per-target (cold-start); (c) it emits
the rule as a first-class artifact (the H in SNG's (H,X)).

## Deliverables (this build)
1. **Target KB** — `cyclic_llm/target_kb/{avb6,pdl1}.json`: mechanism tag, pharmacophore, counter-targets,
   controls, and labeled example sets (actives / non-actives) drawn from this session's data.
2. **Predicate layer** — `cyclic_llm/rule_induction.py`: HELM → logical facts
   (`has_motif`, `position`, `has_turn`, `handle_count`, `ring_size`, `flank_aromatic`, `topology`, ...).
3. **Rule induction** — a lightweight ILP-style learner: find the minimal predicate conjunction present in all
   positives and absent in negatives → the induced `binder(X) :- ...` rule. (First version is a greedy/exhaustive
   conjunction search; swap in Popper/Aleph later for full ILP with recursion/background theory.)
4. **Validation** — the induced αvβ6 rule should reproduce the acceptance_gate (RGD·L + D-Pro + aromatic flanks +
   single handle); emit it as a readable artifact.

## Data (from this session)
- αvβ6 actives: Trivehexin monomer, avebehexin, the published lead `c[FRGDLAFp(NMe)K]`. Non-actives: RGD-dead /
  scrambled decoys + the handle-less v2 set that failed review.
- PD-L1 actives: 5O45 macrocycle control, K-05 (validated selective). Non-actives: the G2 PD-L2-preferring
  pan-binders (negatives for a *selectivity* rule).

## How it plugs in (next builds, not this one)
- Induced rule → (a) conditions the own peptide generator (satisfy-by-construction), (b) rejects residual
  violators, (c) emitted with each candidate set.
- Extend the induction beyond pharmacophore to FTO/claim-scope, developability, mechanism (the four rule
  families) once the Target KB + patent KB are populated.
- Verifier loop (metal-aware cofold+MM-GBSA, counter-target, geometry) scores the rule-satisfying survivors.

## Honest scope
First version is a greedy conjunction learner over hand-chosen predicates — a stand-in for full ILP, enough to
prove L1 (induce not hand-code) and emit the rule artifact. Real ILP (Popper/Aleph) + richer background theory is
the follow-on. Induced rules from 2-3 actives are a *prior*, refined by the verifier + more data, not final truth.
