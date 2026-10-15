# Peptide lead-generation system — MASTER (single entry point)

**Date:** 2026-10-15 · Living master consolidating the generation-system work. The detailed docs remain
authoritative for specifics; this is the one place to start. Code: `research/guangzhou_all_atom/cyclic_llm/`.

## Thesis (one paragraph)
The rounds showed binding is the *easy* axis — candidates die on the HARD gates (selectivity vs homolog,
developability, FTO/novelty, mechanism-correct physics, pharmacophore-geometry). So the moat is **not** the
generator; it is the **closed loop of an LLM proposer + a multi-constraint, honestly-verified scoring stack**
that the generator optimizes against, with the hard gates as IN-LOOP objectives (not post-hoc filters). The
architecture is the **SNG neurosymbolic pattern**: symbolic rules (outside the LLM, deterministic) constrain and
reject; the neural LLM (inside) proposes in the free space; a verifier scores; the loop revises. Knowledge
collection (target / structure / patent KBs) is the prerequisite foundation.

## Division of labor
- **Inside the LLM:** the proposer (candidate generation), intent/language reasoning. Trained only on the
  data-advantaged slices: the peptide/HELM generator + DB-gold tasks (routing/decomp/findings). NOT a general reasoner.
- **Outside (closed loop):** knowledge bases, hard-constraint rules, and the mechanism-matched scoring verifier
  (the reward). Deterministic, correct, fresh.

## What is BUILT and verified (code)
| component | file | status |
|---|---|---|
| Target KB (avb6, pdl1) | `target_kb/*.json` | ✅ |
| Rule induction (SNG L1 — learn the rule from few actives) | `rule_induction.py` | ✅ reproduces the αvβ6 gate from data (0 error); pdl1 honest cold-start |
| FTO claim layer (`in_claim` + DoE) | `fto_kb/ca2998968.json`, `fto_score.py` | ✅ INSIDE / literally-OUTSIDE+DoE / OUTSIDE(form) |
| Rule-conditioned generator (SNG L2/L5) | `rule_conditioned_generator.py` | ✅ rejects rule-violators AND patent-infringing; ranks by patent risk; emits (H,X) |
| Consolidated verifier/reward `score()` | `score.py` | ✅ cheap tier live (rule+FTO+developability, hard-gate+rank); expensive-tier hooks |
| Closed optimizer loop | `loop.py` | ✅ propose→score→select→revise→repeat closes end-to-end; 0-abandoned convergence on infringing/greasy/rule-fail stress seeds; revise = labeled stand-in for RL/LLM driver |

The **cheap, deterministic half of the loop is built and working** (induce rule → generate FTO-clean by
construction → score → revise → repeat, now closed end-to-end in `loop.py`). The proposer (enumeration) and the
revise operator (deterministic repair) are labeled stand-ins for the neural generator / learned driver. The
**expensive half** (metal-aware cofold+MM-GBSA, counter-target, groove, geometry) exists as validated GPU
pipelines from the program work but is not yet auto-dispatched from `score()`.

## SNG learnings applied (`20261015_DETAILED_DESIGN_SYMBOLIC_NEURAL_LEARNINGS.md`)
L1 induce the design rule from the few actives (not hand-code) ✅; L2 rules condition + reject ✅; L3 emit (H,X)
artifact ✅; L4/L5 fits cold-start + correctness-by-construction ✅. Extend beyond SNG: induce/encode FTO,
developability, mechanism as symbolic specs too (partially — FTO is encoded).

## Next items (prioritized; `20261015_PROGRESS_AND_NEXT_ITEMS.md` has detail)
1. Neural peptide generator (HELM/BoltzGen) replacing the enumeration stand-in.
2. ~~Optimizer loop~~ ✅ DONE (`loop.py`) — remaining: swap the deterministic revise for the learned driver (REINVENT/Saturn RL with `score()` as reward, or LLM-revise); folds into #1/#8.
3. Expensive-tier auto-dispatch into `score()` (GPU physics, control-anchored).
4. Mechanism-matched scorer config (Target KB tag → scorer).
5. Patent compound layer (SureChEMBL/Google Patents ingestion; add PD-L1 + counter-integrin estates).
6. Real ILP (Popper/Aleph) + richer rule families + more negatives.
7. Governance (Mozi verifiable stages).
8. Own-LLM: continue gold SFT → peptide generator → RLVR with `score()` as reward.

## Document index (detailed docs)
- Lessons: `20261015_LESSONS_AND_GENERATION_SYSTEM_UPGRADE.md`
- Survey + architecture (OSS: REINVENT4, Saturn, Mozi, AgentD, SNG, patentability-constrained): `20261015_GENERATION_SYSTEM_SURVEY_AND_ARCHITECTURE.md`
- Two-phase build spec: `20261015_LOOP_BUILD_SPEC_PHASE0_AND_PHASE1.md`
- Own-LLM direction: `20261015_OWN_LLM_OPTIMIZATION_DIRECTION.md`
- SNG learnings + detailed design: `20261015_DETAILED_DESIGN_SYMBOLIC_NEURAL_LEARNINGS.md`
- First-build plan: `20261015_BUILD_PLAN_TARGET_KB_AND_RULE_INDUCTION.md`
- Backlog: `20261015_GENERATION_SYSTEM_BACKLOG.md` · Progress + next: `20261015_PROGRESS_AND_NEXT_ITEMS.md`
- Program context (the αvβ6/PD-L1 rounds this was learned from): `20261014_CYCLIC_PEPTIDE_PROGRAM_MASTER.md`

## Honest framing
The deterministic half works end-to-end and is genuinely novel for peptides (the OSS loops are all
small-molecule). Scores are relative/feasibility-level; the wet-lab assay is ground truth. The remaining builds
(neural generator, automated loop, expensive-tier dispatch) are specified and grounded in components that already
exist — assembly + hardening, not greenfield.
