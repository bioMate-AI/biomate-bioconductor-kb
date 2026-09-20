# Committee Audit v3 — post-training (data, design, tasks, output, error analysis)

**2026-09-20.** gpt-5.6 + gemini-3.8-flash + Claude, on the trained 4B/27B + eval + error analysis
(full accurate brief). **Both models converged unanimously**, and a coverage computation confirms the
core finding with hard numbers.

## Verdict (unanimous)
The models learned **catalog ROUTING, not open-world SYNTHESIS**. 27B > 4B (capacity), both below the
0.54 frontier on out-of-catalog — but the gap is **not uniform mediocrity; it's the niche long tail.**

## The evidence that reframes everything
- **Coverage (computed):** **78% of workflows (3,268/4,172) are NEVER a gold target** in the 18,597-ex
  SFT set; only 22% appear; top-10 hog 21% of refs. Composition-relevant sets (decompose+interwf+wfgen
  = 5,528) ≈ 1.3 ex/workflow if uniform (they're not). **We trained a head-heavy catalog lookup engine.**
- **27B is BIMODAL** (gemini's key reframe): on the 60 non-zero cases its coverage ≈ **0.53 ≈ the 0.54
  frontier baseline**; it's frontier-competitive *where knowledge + retrieval exist*, and dead-zero on
  20 niche cases. So the entire deficit = the long tail, not general weakness.
- **Dual sparsity is the root cause:** niche zero-coverage = (a) retriever ~0 recall on unseen families
  (family-holdout recall 0.40 → wrong/no tool blocks supplied ~60% of the time) + (b) base model never
  saw the niche tool tokens because **mid-training (44.9M corpus) was SKIPPED**. Note: some failing
  workflows *had* SFT examples (oncomix 5, pipecomp 12) yet scored 0 → also a **task-OOD** effect (the
  removal task was never supervised; routing SFT taught "pick one known workflow").
- **27B mode collapse:** `composed_rate 0.05` = the routing-heavy loss (routing 36.5% vs composition
  11.5%) suppressed the multi-step grammar; high capacity over-optimized the single-pick attractor. The
  4B *underfit* the shortcut, ironically keeping format compliance (composed 1.0).

## Per-dimension findings
- **DATA (P0):** 78% workflows unseen; Zipfian head-bias; transcriptomics ~55% of eval (aggregate is a
  transcriptomics score). Missing coverage tables now computed. → report **macro-average** + CIs.
- **DESIGN (P0):** **skipping mid-training was the critical error** — the 44.9M corpus exists to inject
  niche tool/ontology/WKG knowledge; base→SFT met niche tokens first under instruction loss →
  hallucinate/refuse. SFT-first is fine for schemas/routing/clarification, not open-world synthesis.
- **TASKS (P0):** removal eval tests generalization **never supervised** (OOD). Add explicit
  catalog-ablation composition + retrieval-grounded multi-block planning. Retriever recall@1 is the
  wrong primary metric for multi-step tasks.
- **OUTPUT:** 0.30/0.40 vs 0.54 is **not a fair generative verdict** — depressed by format
  (composed_rate) + judge noise (edgeR≡DESeq2 both valid) + retrieval failure baked in. Isolate them.
- **ERROR:** two phenotypes — niche zero-coverage (dual sparsity) and 27B bimodality (routing shortcut
  vs format rigidity).

## Reshaped plan — highest-priority fixes BEFORE v3 compositional SFT (both members agree)
1. **Run the 44.9M-token mid-training pass** (domain adaptation) on both bases first — inject niche
   tool/ontology/WKG knowledge. This is the top pre-v3 intervention (it was wrongly skipped).
2. **Rebalance SFT**: cut routing share, greatly increase composition/decomposition, and **cover the
   78% unseen workflows** (at least their tool-functions) — long-tail-balanced sampling.
3. **Isolate failure sources** in the eval: report retrieval-recall (family + on the niche zero set),
   generation-given-correct-context, schema validity, judge agreement — separately.
4. **Inject the WKG 1-hop precede/succeed subgraph at inference** (gemini's single highest-impact
   change) instead of relying on parametric memory or sparse retrieval for tool connectivity.
5. **Enforce structured-output grammar** in SFT (fixes 27B mode collapse; drop brittle composed_rate).
6. **Macro-average + confidence intervals**; sealed workflow-FAMILY holdout for all claims.

## Single highest-priority action
**Domain-adaptive mid-training on the 44.9M corpus (long-tail-weighted), then rebalanced compositional
SFT** — with the eval decomposed into retrieval vs generation. Raw reviews: `committee_reviews/audit_v3_*.md`.
