# Generation-system — detailed progress + next item list

**Date:** 2026-10-15 · Detailed state of the peptide lead-generation system build and the prioritized next items.
Code lives in `research/guangzhou_all_atom/cyclic_llm/`. Design refs: the five 20261015 architecture/spec docs.

## Built so far (working code, verified)
| component | file | what it does | verified behavior |
|---|---|---|---|
| **Target KB** | `target_kb/{avb6,pdl1}.json` | per-target: mechanism tag (metal? epitope?), controls, counter-targets, labeled actives/non-actives | loaded by induction + score |
| **Rule induction (SNG L1)** | `rule_induction.py` | HELM→predicates; greedy discriminative-conjunction learner induces `binder(X):-...` from few actives | avb6: `has_rgd, has_rgdl, flank_aromatic_p1, flank_aromatic_p7` — 3/3 pos, 4/4 neg, 0 err (reproduces hand-gate from data); pdl1: noisy at 1 active (honest cold-start) |
| **FTO claim layer** | `fto_kb/ca2998968.json`, `fto_score.py` | structured genus claim; `in_claim` maps candidate→X1–X7 → INSIDE / literally-OUTSIDE(pos)+DoE / OUTSIDE(form); + patent seq-identity | avebehexin INSIDE; 2Nal flank OUTSIDE-X4 MED; Ser@X3 HIGH; 7-mer OUTSIDE(form) MED; lactam OUTSIDE(form) LOW |
| **Rule-conditioned generator (SNG L2/L5)** | `rule_conditioned_generator.py` | conditions on induced rule + KB mechanism; satisfies by construction; **rejects rule-violators AND patent-INFRINGING**; ranks survivors by DoE then patent-id; emits (H,X) | all-canonical (genus) auto-rejected; survivors = ncAA-flank, MED DoE, ranked |
| **Consolidated score() / reward** | `score.py` | merges cheap tier (rule, FTO, developability) inline + expensive-tier hooks (binding dG, selectivity gap, groove, geometry from GPU pipeline); hard-gate verdict + rank key | avebehexin gate=False(infringing); clean ncAA gate=True; di-2Nal gate=False(greasy+rule) |
| **Closed optimizer loop** | `loop.py` | `propose (gen_avb6) → score() → select (freeze gate-passers) → revise → repeat`; revise = deterministic, score-record-reading repair operator (honest stand-in for the LLM-revise move) that reads the failing objective and applies one targeted free-position edit; trace distinguishes revised/converged/abandoned | 3 deliberately-failing seeds (infringing, greasy, rule-fail) all converge into the gated set in 2 rounds; **0 abandoned**; final = 5 FTO-clean MED-DoE de-greased candidates, Pareto-ranked by `score.rank_key` |

## Architecture as realized (SNG pattern, working)
- **Symbolic (outside LLM):** induced rule (L1) + FTO claim constraint + developability — deterministic, cheap,
  used to CONDITION generation + REJECT violators (L2) + emit (H,X) (L3).
- **Neural (inside LLM):** the proposer — currently a rule-constrained enumeration STAND-IN; the HELM/BoltzGen
  peptide LLM slots in here next.
- **Verifier/reward:** `score()` — cheap tier live; expensive tier (metal-aware cofold+MM-GBSA, counter-target,
  groove, geometry) hooks into the GPU pipeline results we built this session, control-anchored (A2).

## Next item list (detailed, prioritized)
1. **Replace the enumeration stand-in with the neural peptide generator (Phase 1.1).**
   - Wire HELM/BoltzGen as the proposer behind `gen_*`; pass the induced rule + FTO constraint as conditioning;
     keep the reject+rank. Deliverable: generator that proposes *diverse* free-position chemistry (not enumerated),
     still FTO-clean by construction.
2. ~~**Close the optimizer loop (Phase 1.2).**~~ **✅ DONE — `loop.py`.**
   - Built the loop HARNESS: `propose → score() → select (freeze gate-passers) → revise → repeat`, returns the
     Pareto-ranked gated set + a per-round revise trace. The `revise` operator is the deterministic,
     score-record-reading repair (honest stand-in for the LLM-revise move); it slots out for driver (a)
     REINVENT4/Saturn RL with `score()` as reward, or (b) the neural/LLM revise, when those land.
   - Verified: 3 deliberately-failing seeds (infringing / greasy / rule-fail) converge into the gated set,
     0 abandoned. **Remaining for this item:** the learned drivers (RL policy or LLM revise) replacing the
     deterministic repair — folds into items #1 (neural generator) and #8 (own-LLM RLVR).
3. **Expensive-tier integration into score() (Phase 0.6).**
   - Auto-dispatch the GPU pipeline (metal-aware cofold+MM-GBSA, counter-target, groove, geometry) for gate-passing
     candidates; cache results; enforce A2 control-anchoring (scores inadmissible if controls fail). Deliverable:
     `score(..., tier="full")` that fills binding/selectivity/groove/geometry.
4. **Mechanism-matched scorer config (Phase 0.7).**
   - Target KB `mechanism` tag → auto-configure the scorer (inject metal for integrins; cofold vs dock by epitope).
5. **Patent/FTO compound layer (Phase 0.5 follow-on).**
   - Ingest SureChEMBL / Google Patents Public Datasets → real nearest-patented dissimilarity (replace the
     known-compound seq-identity stub). Add PD-L1 (BMS macrocycle estate — source-verify) + counter-integrin patents.
6. **Real ILP (method upgrade).**
   - Swap the greedy learner for Popper/Aleph with background theory + recursion; richer negatives per target
     (pdl1 cold-start needs more non-actives). Extend induction to FTO/developability/mechanism rule families.
7. **Governance (Phase 1.3, Mozi pattern).**
   - Verifiable stages + provenance + honest "feasibility-level, not absolute" labels on every output.
8. **Own-LLM track (parallel).**
   - (B) continue DB-gold SFT (routing/decomp/findings); (A) stand up the peptide/HELM generator; then RLVR with
     `score()` as reward once the loop produces volume. Always validate vs frontier on the narrow slice.

## Honest state
Cheap, deterministic half of the loop (rule + FTO + developability + generation-by-construction + reward merge)
is **built and verified**, and the **loop harness now closes end-to-end** (`loop.py`: propose → score → revise →
repeat, 0-abandoned convergence on the stress seeds). What is still a labeled STAND-IN: the proposer
(enumeration, not neural — item #1) and the revise operator (deterministic repair, not a learned RL/LLM policy —
folds into #1/#8). The expensive half (physics scoring) exists as validated GPU pipelines from this session but
is **not yet auto-dispatched from score()** — item #3. Scores remain relative/feasibility-level; wet-lab assay
is ground truth.
