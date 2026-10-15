# Generation-system build backlog (item list)

**Date:** 2026-10-15 · Prioritized item list for the peptide lead-generation system upgrade. Status:
[x] done · [~] in progress/partial · [ ] todo. Refs: survey/architecture, Phase0+1 spec, own-LLM direction,
SNG-learnings, build plan docs (all 20261015).

## Phase 0 — knowledge collection
- [x] **Target KB** (avb6, pdl1) — mechanism tag, controls, counter-targets, labeled examples → `cyclic_llm/target_kb/`
- [x] **ILP-style rule induction (SNG L1)** — induce the design rule from actives → `rule_induction.py`
      (avb6: `has_rgd, has_rgdl, flank_aromatic_p1, flank_aromatic_p7`, 3/3 pos 4/4 neg, 0 error)
- [x] **Rule-conditioned generator (SNG L2/L5)** — constrain + reject + emit (H,X) → `rule_conditioned_generator.py`,
      `avb6_generated_HX.json`
- [~] **Structure KB** — avb6_ourstructure_v1 done; add pdl1 + counter-target receptors; metal-aware prep recipe; ensembles later
- [ ] **Patent/FTO KB** (BIGGEST LIFT) — claim layer (generalize the CA2998968 read into `in_claim`) + compound DB
      (SureChEMBL / Google Patents, InChIKey/sequence index) → `fto_score(candidate)`
- [~] **Verifier stack** — wrap session scorers (metal-aware cofold+MM-GBSA, counter-target, groove, geometry,
      developability) into ONE control-anchored multi-objective `score()`
- [ ] **Mechanism-matched scorer config** — Target KB mechanism tag auto-configures the scorer (inject metal, pick cofold vs dock)

## Phase 1 — closed loop
- [~] **Generator** — rule-conditioned enumeration stand-in done; wire the neural peptide LLM (HELM/BoltzGen) as proposer
- [ ] **Optimizer loop** — propose→score→revise; REINVENT4/Saturn-style RL + LLM-in-the-loop revise (the SL-01→SL-v3 move); multi-objective (not binding-then-filter)
- [ ] **Governance (Mozi pattern)** — verifiable stages + hard constraints + provenance; honest feasibility-level labeling

## Own-LLM track (separate)
- [~] **(B) DB-gold SFT slices** — routing/decomp/findings (prior SFT-from-gold result); continue + expand gold from the loop
- [ ] **(A) Peptide/HELM generator** — train/fine-tune on peptide binders + scored candidates; the cyclic-LLM thesis
- [ ] **RLVR from the verifier** — use the verifier stack as reward (SFT → DPO → RL) as the loop produces volume; validate vs frontier

## Method upgrades
- [ ] **Real ILP** (Popper / Aleph) replacing the greedy conjunction learner — recursion + background theory
- [ ] **Extend induction** to FTO / developability / mechanism rule families (not just pharmacophore)
- [ ] **Richer example sets** — more non-actives/decoys per target to strengthen induction (pdl1 cold-start noisy at 1 active)

## Recommended order
1. Patent/FTO KB (§0.5) — highest-value gap; makes generation FTO-aware by construction.
2. Verifier stack + mechanism-matched config (§0.6–0.7) — the reward.
3. Optimizer loop automation (§1.2) — close the design→score→redesign loop.
4. Then own-LLM: expand gold SFT, stand up the peptide generator, RLVR.
(Real ILP + richer rule families fold in alongside as data grows.)
