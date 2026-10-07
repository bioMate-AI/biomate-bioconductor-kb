# Two best-cyclic-LLM levers — HELM/ncAA representation + unified multi-target selector

**Date:** 2026-10-07 · Program-level progress toward the best LLM + system for cyclic peptides. Two levers
built and run on real data this session; both positive.

## Lever 1 — HELM/monomer (ncAA-native) representation
`cyclic_llm/train_helm_monomer_llm.py`, `results/helm_monomer_llm_eval.json`.
The v2/v3/selector LMs tokenize over the 20 canonical AAs (chars) — they cannot represent the
N-methyl / D-amino / ncAA / modified monomers real macrocyclic drugs are made of. This LM tokenizes over a
**monomer vocabulary** built from CycPeptMPDB: **387 tokens, 363 of them ncAA/modified** (meL, dP, Sar,
Nle, Ser(tBu), Me_Bmt(E), …). Property-conditioned on measured permeability (logPapp). Result (3000 steps):
- **validity 1.0**, novelty 1.0, **mean ncAA fraction 0.66** (generates genuinely ncAA macrocycles, not
  collapsing to canonical AAs).
- **permeability conditioning Δ+0.40** (hi-conditioned logPapp −5.74 vs lo −6.14 → hi designs ~0.4 log
  units more permeable), scored by a held-out composition regressor on measured permeability.

→ The LM now generates arbitrary-chemistry (ncAA/N-methyl/D-AA) cyclic peptides natively with working
property control — the representation upgrade the char-LM could not express.

## Lever 2 — unified multi-target binding selector (one model, all targets)
`cyclic_llm/unified_selector.py`, `results/unified_selector_eval.json`.
One target-conditioned LM trained jointly on ALL 5 display targets (569,612 records; per-record
target-feature prefix + enrichment-bucket token), used as a selector (LLR = logP(seq|target,hi) −
logP(seq|target,lo)), evaluated per-target on held-out SEQUENCES.

| target | unified AUC (one model) | single-target AUC | lift@5% |
|---|---|---|---|
| PADI4 | 0.958 | 0.968 | 9.3× |
| Abeta42 | 0.983 | 0.988 | 3.5× |
| hIAPP | 0.669 | 0.681 | 4.7× |
| **hPCSK9** | **0.815** | **0.344 (failed in isolation)** | 2.1× |
| **FIKK13** | **0.843** | n/a (38 binders, too few for a solo model) | 11.6× |

Three findings:
1. **One model matches the per-target selectors** on the strong targets (PADI4/Abeta42/hIAPP) — so a
   single deployable "binding brain" serves all targets, no per-target models needed.
2. **Joint training RESCUES hPCSK9** (0.344 → 0.815). **Honest correction:** hPCSK9's earlier "genuine
   target-specific failure" was a **data-isolation** artifact, not the target being fundamentally hard —
   cross-target representation sharing fixes it.
3. **Enables data-poor FIKK13** (38 binders → AUC 0.843) — a target with too few binders to train a solo
   selector works inside the multi-target model.

→ This is the deployable system shape: one target-conditioned binding brain, as good as per-target models
AND stronger on weak/sparse targets via shared representation. (Still within-target per target — NOT
cross-target zero-shot, which stays the v3.1 field-wide null.)

## Where this puts the program
- **Best-LLM core:** ncAA-native generation (Lever 1) + a unified binding selector that matches/rescues
  across targets (Lever 2) — both the generation and the binding-brain now operate at the chemistry and
  multi-target scale a real cyclic-peptide LLM needs.
- **System:** data → our LLM (ncAA generate + multi-target select) × base BoltzGen (structure) → MO/QC →
  closed loop → FTO gate. The LLM halves are now demonstrated at representation + scale.
- **Honest frontier (unchanged):** cross-target zero-shot (open field-wide); end-to-end wet-lab closed-loop
  validation; richer target features for the data-poor regime.
