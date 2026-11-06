# Lessons from the cyclic-peptide optimization rounds + how to strengthen the LLM+knowledge lead-generation system

**Date:** 2026-10-15 · Synthesis of what the αvβ6 / PD-L1 cyclic-peptide rounds taught us, and a concrete plan
to upgrade the generative system. Thesis up front: **the system generates mechanism-valid binders easily; the
value — and where candidates actually die — is the HARD constraints (selectivity, developability, FTO/novelty,
mechanism-matched physics, pharmacophore-geometry). The upgrade is to move those from post-hoc filters into
in-loop generation objectives.**

## 1. What the rounds empirically showed (binding is easy; the hard gates kill everything)
| round | outcome | lesson |
|---|---|---|
| αvβ6 rule-gated monomers | all pass pharmacophore, **all FTO-blocked** (Notni genus) | a rule that fixes the whole scaffold can only emit molecules INSIDE the patented genus. Rules = good FILTER (mechanism), poor GENERATOR (novelty). |
| PD-L1 G1 (10) → 1 selective | binders easy; only K-05 clears PD-L2 | **selectivity vs the homolog is the bottleneck, not affinity.** |
| PD-L1 G2 (24) → 0 selective | 24/24 fold, 8/8 groove, **0/8 PD-L1-selective** | more binders ≠ more leads; the generator optimized binding, was blind to the counter-target → pan-binders. |
| developability (2Nal/multi-Trp) | greasy candidates ranked high by MM-GBSA | **scoring functions over-reward hydrophobic burial**; the generator exploits that bias → false positives. |
| αvβ6 affinity (metal-free) | weak/**positive** ΔG — physically invalid | **physics must match mechanism** (integrin RGD needs the MIDAS metal); a generic scorer silently gives wrong answers. |
| αvβ6 scaffold-hop (lactam) | naive build held the RGD Asp **1 Å short**; geometry-guided redesign (SL-v3) fixed it (2.01 Å) | **scaffold changes need a pharmacophore-geometry-fidelity check** — "it contains RGD" ≠ "it presents RGD correctly." |

**Meta-lesson:** generating a mechanism-valid *binder* is the easy axis (frontier LLMs + pharmacophore rules do
it). Candidates died on **selectivity, developability, FTO/novelty, mechanism-correct physics, and geometry
fidelity** — axes the generator did NOT optimize. Generate-on-binding-then-filter-on-everything collapses yield
to ~0. The hard gates must become generation objectives.

## 2. How to strengthen the LLM+knowledge system (prioritized)
1. **Close the loop: design → score → redesign (highest leverage).** The one place we turned a failure into a
   win (lactam SL-01 → SL-v3) was a closed loop: propose, score geometry, revise. Generalize this — the LLM
   proposes, a fast multi-objective verifier ranks, the LLM revises against the verifier. Replace
   generate-then-filter with iterate-against-the-verifier.
2. **Selectivity-aware generation.** The generator was blind to the counter-target (PD-L2). Encode the
   target-vs-counter-target interface DIFFERENCES as a knowledge input (we already computed the PD-L1-vs-PD-L2
   handle residues — that analysis must FEED generation) and score the counter-target in-loop. Design toward the
   distinguishing residues, not just the shared groove.
3. **FTO/novelty-aware generation.** The generator produced genus-blocked αvβ6 monomers because it couldn't see
   the patent landscape. Build a structured patent-claim knowledge base the generator can reason over, so it (a)
   recognizes the claimed genus and (b) generates OUTSIDE it (scaffold-hop, ncAA at free positions, alternative
   cyclization). Novelty/FTO as a hard generation constraint, not an afterthought.
4. **Developability-aware generation.** Add hydrophobicity / aggregation / liability proxies as in-loop penalties
   so the generator can't exploit the scorer's hydrophobic-burial bias (the 2Nal trap).
5. **Mechanism-matched physics (knowledge configures the scorer).** A target-mechanism knowledge layer that
   recognizes metal cofactors (MIDAS), discontinuous vs linear epitopes, etc., and auto-configures the scoring
   pipeline (add the ion, pick cofold vs docking). A generic pipeline silently fails on metal/PPI targets.
6. **Pharmacophore-geometry fidelity for scaffold-hops.** Put the template-docking triage (does the new frame
   present the pharmacophore in the bioactive conformation?) in-loop for any scaffold change — it caught the
   lactam's 1 Å Asp gap and guided the fix.
7. **Strengthen the verifier stack as the reward signal.** The reason results were honest is the gated, control-
   anchored pipeline (A2 control validation, groove occupancy, counter-target, FTO, developability). This IS the
   verifiable-reward loop: the LLM's value is proposing; the harness's value is the cheap, honest verifier.
   Harden the verifier (controls every batch, mechanism-matched physics, calibrated proxies) and make it the
   objective the generator optimizes.

## 3. The honest thesis (what the moat actually is)
Our edge is **not** "the LLM generates binders" — frontier models + rules already do that. The edge is the
**closed loop of LLM generation + a multi-constraint, honestly-verified scoring stack** (selectivity,
developability, FTO, mechanism-matched physics, geometry) that the generator optimizes against. The rounds proved
binding is easy and the hard gates are where value and attrition live — so the system's job is to make those hard
gates IN-LOOP objectives and to PRIORITIZE well, shrinking the experimental search space. The knowledge + verifier
stack and the design-score-redesign loop are the moat, not the raw generator. (Consistent with: composer/execution
is the real gap not the LLM; QC loop = verifiable rewards; KB dividend; model-as-system-component.)

## 4. Honest limits (so we don't over-claim)
Computational scores here are **relative / feasibility-level**, not absolute affinity: single receptor structure
per target, MM-GBSA biases, rigid-overlay geometry, metal params approximate, FTO informational. The system's role
is to **prioritize and de-risk**, not replace experiment. Real validation is the wet-lab binding/selectivity assay.
That honesty is a feature — it's what makes the prioritization trustworthy.
