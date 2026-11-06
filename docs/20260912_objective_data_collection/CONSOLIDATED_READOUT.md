# Consolidated readout — can one model predict the objectives, and what's missing

Date 2026-09-13. Synthesis of parallel workstreams W1–W8. Answers the design question:
what is the logic, is it one model, what's missing.

## The logic (confirmed against canonical OBJECTIVES.md)
ONE mechanistic FM predicts the central-dogma cascade (H1 transcription → H2 translation →
H3 protein → H4 presentation) through a machinery-state bottleneck. The 7–8 "objectives"
are produced by the SURROUNDING SYSTEM, not FM heads:
- **Correct target** ← evidence combiner (W6)
- **Druggable** ← gate (W5)
- **Durable / irAE / tolerance / causal-epitope** ← derived scores off the FM (W8)
- **Clinical efficacy / duration / safety as outcomes** ← explicit NON-GOAL (validation only)

So "one model for 8 objectives" = false framing. It's one FM (mechanism) + combiner + gate
+ derived scores + external validation. Trying to train 8 clinical heads fails on paired-N.

## The one metric that governs everything: PAIRED-N (feature ∧ label), not label-N
| Objective | Role | Held paired-N | Verdict |
|---|---|---|---|
| H1 transcription | FM head | ~70k conditions, >100M cells | **trainable now** |
| H2 translation | FM head | **0** | white space — unpaired + dropout, or generate |
| H3 protein | FM head | ~0 same-flask held (~950–2k public) | fetch+process task |
| H4 presentation | FM head | 1–2 sets, single-HLA | thesis proven (HAP1); no generalization yet |
| Correct-target combiner | system | 2/9 channels validated | logic is the gap, not data |
| Druggability gate | system | 20 targets classified | no cyclic-peptide engagement data |
| Vaccine response | validate | 2,125 / 6,819 labels | usable validation |
| Safety | validate | 248 baseline / 7,001 labels | too small — exploratory only |
| Therapy duration | validate | 341 subj (0 molecular pairs) | cohort-level validation only |

## What's missing, ranked
1. **Paired multi-HLA mechanistic data (W7) — THE moat.** Only 2 same-flask paired triples
   held, both single-HLA. H2/H3/H4 not trainable beyond one cell line. → (a) FETCH the
   ~25–30 identified public deposits (zero wet-lab) to widen H4 to ~4–7 HLA; (b) then a
   minimal CRO atlas (~6 HLA lines × 5 KO+WT × T+P+L ≈ 72 units) to close leave-line/leave-KO-out.
2. **H2 translation data** — essentially absent; the deepest single hole.
3. **Evidence-gated combiner logic (W6)** — data is present (8/9 channels); the averaging
   combiner is a clean negative. Build OR-nominate / AND-corroborate + null-gap weighting.
4. **Cyclic-peptide engagement + interface-structure data (W5)** — gate is heuristic; no
   measured macrocycle binding, no hotspot analysis, no permeability for intracellular targets.
5. **Validation depth** — clinical sets are label-rich but pairing-poor; fine as external
   validation of derived scores, not as training.

## Immediate no-wet-lab actions that move the needle
- Fetch the H4 KO-immunopeptidome backlog (W7) → 1 → ~4–7 HLA for the differentiator head.
- Fetch + process public H3 proteome pairs (~950–2k) → unblocks H3-delta baseline.
- Build the evidence-gated combiner (W6) → first real "correct-target" output with breakdown.
All else (H2, multi-HLA H4 generalization, cyclic-peptide validation) needs generation, not scraping.
