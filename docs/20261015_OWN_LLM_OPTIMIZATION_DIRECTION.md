# Own-LLM optimization — what to continue (vs the harness)

**Date:** 2026-10-15 · The knowledge bases + closed loop are the *harness*; the own LLM is a separate asset.
This defines what the own LLM should be optimized for — only the slices the harness cannot carry — and how.
Consistent with: harness/LLM task split, SFT-from-gold result, KB-dividend, model-as-system-component,
cyclic-LLM thesis, on-prem-uses-own-model, no-tiny-dataset.

## 1. Division of labor — what the LLM uniquely owns
The harness (deterministic, verifiable) owns: retrieval, rule/constraint checking, FTO claim logic, the
physics/scoring verifier, selection. A frontier model + KB already does the *general planning/reasoning* well
(and the KB-dividend result says context helps weaker models more — so don't train a weak own-model to reason).
**What is LEFT for the own LLM is the data-advantaged, generative slice the frontier is NOT trained on:**
1. **Peptide/macrocycle GENERATION** — proposing synthesizable, mechanism-valid cyclic-peptide chemistry (HELM /
   sequence / ncAA / scaffold) in the free space. This is a specialized output distribution; rule-enumeration is
   genus-bound and a general LLM has no peptide-chemistry prior. A HELM-native model trained on peptide data +
   our scored candidates genuinely proposes better than either.
2. **DB-gold-bound task slices** — routing, decomposition, findings — where we have proprietary validated gold
   the frontier lacks (the SFT-from-gold result already showed this fixes the routing regression + decomp).

Everything else (reasoning, orchestration, deterministic checks) stays frontier + harness.

## 2. What to continue (prioritized)
**A. Continue SFT on collected DB gold (proven; keep going).** The findings/tool/decomposition SFT already
delivered measured gains (routing regression fixed, decomp node-F1 0.36→0.73). Expand the gold set as the closed
loop produces more validated (design → score → outcome) tuples. This is the lowest-risk, data-advantaged moat.

**B. Invest in the peptide/HELM GENERATOR (the cyclic-LLM thesis).** Train/fine-tune a HELM/sequence-native
generator on: known peptide binders, our generated+scored candidates, and (as it arrives) assay outcomes. Goal:
propose candidates that are synthesizable, mechanism-valid, and *diverse in the free positions* (ncAA, scaffold-
hops) — exactly where rules fail (genus trap) and a general LLM has no prior. This is the generator in the SNG
loop; the symbolic rules constrain it, but the quality of proposals inside the free space is the own-LLM's job.

**C. RLVR — learn from the verifier (the frontier move).** The closed-loop verifier stack (binding, selectivity,
developability, FTO, geometry, control-anchored) IS a verifiable reward. Use it to fine-tune the generator so it
internalizes "propose candidates that pass ALL the hard gates," not just binding — the exact failure mode of this
session (G2: 24 binders, 0 selective). Sequence: SFT first (B), then preference/RL optimization (DPO → RL) with
the verifier as reward as the loop produces volume. This is "QC loop = verifiable rewards" applied to generation.

## 3. The co-evolution (why the loop and the LLM are coupled)
The closed loop GENERATES the own-LLM's training data: every (candidate, multi-objective score, eventual assay
outcome) tuple is a labeled example. So loop → labeled data → SFT/RL the generator → better proposals → loop.
The harness and the own-LLM are not independent tracks; the harness is the LLM's data factory and reward source.
This is the concrete form of "invert the data dependency" — our own scored/assayed peptide data, which no
frontier model has.

## 4. What NOT to over-invest in (honest)
- **General reasoning / concept-CPT on the own model.** Frontier + KB already reason/plan; the KB-dividend result
  says context helps weak models more → use a strong model + KB for reasoning, don't train a weak own-model to it.
  The moat is SFT/RL on DB gold for the LLM-bound slice, not concept-CPT.
- **Tiny-dataset LLM experiments** (no-tiny-dataset rule) — the loop must produce enough volume first; don't draw
  conclusions from toy data.
- **Making the own-LLM do the deterministic work** (FTO checks, scoring) — that's the harness; keep it out of the model.

## 5. Honest guardrails
- **Always compare the own-LLM vs frontier** (on-prem-uses-own-model): the own model must *beat* frontier on its
  narrow slice (peptide generation, gold-bound tasks) to justify itself; on general tasks it won't, and shouldn't
  be used there.
- **Data volume gate:** generation-quality RL needs the loop producing scored candidates at volume, and ideally
  assay outcomes closing the outer loop. Don't start RLVR before there's a real reward signal distribution.
- **Scores are feasibility-level** until assay data returns — so early reward is the verifier (relative), later
  reward is assay outcome (ground truth). Weight accordingly.

## Summary
Continue the own-LLM on exactly two data-advantaged slices the harness can't carry: **(A) the peptide/HELM
generator** and **(B) the DB-gold task slices (routing/decomp/findings)** — via **SFT on gold now, RLVR from the
verifier as the loop matures.** The loop is the data factory + reward source (co-evolution). Do NOT train the own
model to be a general reasoner — that's frontier + KB. The moat is the generator + gold-SFT/RLVR slice, validated
against frontier.
