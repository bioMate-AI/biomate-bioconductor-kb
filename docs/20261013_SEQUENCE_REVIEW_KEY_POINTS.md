# Molecule (peptide) sequence review — key points, and the gate that must precede wet-lab

**Date:** 2026-10-13 · The checklist every candidate sequence must pass **before synthesis / wet-lab**,
plus an honest post-mortem of why mechanism-dead sequences reached the CRO-order stage in round-1 and the
rule that prevents recurrence. Synthesizes the program's experience + the 靶理 (target-logic) doctrine.

## 0. Honest post-mortem — why this matters (own it)
Round-1 ran **BoltzGen generation → iptm composite / MM-GBSA ΔG → FTO → CRO order** — with **no hard
pharmacophore gate**. Result: the αvβ6 panel that reached the GenScript CRO-order stage was **0/12 RGD,
0/12 Asp** — mechanism-dead by construction (an RGD integrin ligand with no RGD cannot engage the MIDAS
metal). A one-page review (`sequence_audit.json`, the 靶理 framing) caught it *immediately* because it
asked the **first-principles question the automated pipeline never encoded**: *does the molecule even carry
the pharmacophore?* The pipeline optimized *binding-proxy scores* (iptm, ΔG) as if a good score implied
target recognition — it does not. A learned/physics score can rank a non-binder "excellent." **That gap —
score-optimization without a mechanism gate — is exactly how expensive wet-lab waste happens.** The fix
(now in place: `pharmacophore_knowledge.py` hard gate + liability + FTO, re-gated in v2) is cheap, exact,
and runs in milliseconds; it should have been the *first* filter, not a post-hoc audit. The lesson below is
item 2, and it is non-negotiable.

## The checklist (apply to every candidate, in order)

1. **靶理 first — classify every position before touching anything.** Each residue does a different job:
   - **grabber / pharmacophore-core** (directly recognizes the target — e.g. αvβ6 RGD·Asp→MIDAS): **do not edit**;
   - **scaffold** (sets the bound conformation — e.g. D-Pro + N-methyl lock): editing changes shape → function;
   - **editable / cleavage-prone** (solvent-facing, protease/chemistry hotspots): **this is where you improve**.
   Edit the grabber → lose the target; edit the scaffold → change the shape; edit the right liable position →
   gain stability while keeping activity.

2. **Hard mechanism gate BEFORE any score (the round-1 lesson).** Does the candidate carry the *known*
   pharmacophore? (αvβ6: RGD + the selectivity Leu `RGDL` + D-Pro/N-methyl lock; PD-L1: the IgV-cleft
   amphipathic chemotype, structure-gated.) A candidate lacking it is mechanism-dead **regardless of iptm or
   ΔG**. This gate is exact, free, and must run first — never ship a sequence a score "liked" but the
   mechanism rejects.

3. **Binding ≠ function — report three axes together, never one.**
   - **affinity** (Kd / ΔG — does it stick),
   - **functional efficacy** (does it *do* anything — block/agonize/antagonize; "still binds" ≠ "still works"),
   - **selectivity** (vs off-target receptors — e.g. αvβ6 vs αvβ3/αvβ5/αvβ8; a bare RGD binds them all).
   A high binding score alone says only "may stick," not "works" and not "specific."

4. **Scores are necessary-not-sufficient and will pass non-binders.** iptm / MM-GBSA optimize a
   binding *proxy*; without the mechanism gate they rank mechanism-dead sequences highly. Never let a
   learned or physics score substitute for the first-principles pharmacophore question.

5. **Find editable positions empirically where possible** (don't assume from literature alone):
   **truncation** (what deletes without losing activity), **alanine-scan / deep-mutational-scan** (per-position
   importance → which residue recognizes vs. maintains structure), **degradation-product mapping** (locate the
   actual protease cut site — edit *there*, not the whole chain).

6. **Developability / CMC liabilities are the edit targets.** Deamidation (N-G, N-S), Asp isomerization
   (D-G, D-S, D-P), Met/Trp oxidation, free/odd Cys, aggregation (excess hydrophobicity). Fix at the liable
   position; preserve the grabber. (For a renally-cleared radioligand, also net charge → kidney dose.)

7. **Don't attribute all effect to one change.** Octreotide (D-AA + disulfide + terminal mods, together) and
   semaglutide (Aib8 for DPP-4 resistance *plus* lipid/albumin for half-life) show effects come from
   *coupled, synergistic* modifications. State per change which *specific* bottleneck it addresses; don't
   over-credit "cyclize" or "shorten." Preserve the function the *therapy* needs, not every natural activity.

8. **FTO is an IP axis, not an activity axis.** Distinguish re-discovery (too close to a patented genus) from
   novelty — but keep it separate from the activity/cliff question; a novel sequence is not automatically active.

9. **Activity cliffs.** Near-identical sequences can have opposite function (RGD binds, RGE does not; L-Pro
   vs D-Pro; N-methyl on/off). Treat key positions as **hard constraints**, use a stereo/N-methyl-aware
   representation, and let physics/wet-lab arbitrate at the cliff — never trust a smoothed similarity score there.

10. **Per-round discipline — state three things before every experiment:** (a) the *specific bottleneck* this
    round addresses; (b) *what* you change and *why* (which position, which guideline, which tradeoff); (c)
    *how* you read out **all three** axes (affinity + efficacy + selectivity).

11. **Gate before CRO (the hard rule).** No sequence advances to synthesis/wet-lab until it passes:
    pharmacophore (mechanism) + liability (CMC) + FTO (IP) + a **multi-reviewer sanity check**. Round-1's
    0/12-RGD panel reaching the order stage is the cost of skipping this; a 2-minute review would have caught it.

## Operational consequence for this program
- The computational pipeline (cofold iptm, MM-GBSA ΔG) covers **axis 1 only (binding)**. Functional efficacy
  and selectivity are **wet-lab legs** (PD-L1: PD-1/PD-L1 blockade reporter; αvβ6: integrin-selectivity panel).
  Results are labeled **"binding prediction,"** never "active/selective."
- The pre-CRO gate is now: `pharmacophore_knowledge.py` + `knowledge_liability_flags.py` + `drug_novelty_fto.py`
  + **a cross-model committee review** (see `20261013_LLM_COMMITTEE_REVIEW.md`) — run on v2 *before* any
  synthesis, this time.
