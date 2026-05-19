# GLP-1 modality bakeoff — why "the next GLP-1" is an indication question, not a chemistry question

*Semaglutide (Ozempic/Wegovy, Novo Nordisk) hit $42 billion in 2024. Tirzepatide (Mounjaro/Zepbound, Eli Lilly) hit $36 billion. Retatrutide (Lilly Phase III) and orforglipron (Lilly Phase III oral) are queued behind. Every pharma in the world is asking the same question: what's the next GLP-1? The answer depends on what you're treating — not what you'd like to put in a vial.*

---

## The receptor pattern decides everything

The GLP-1 family has three receptors:

- **GLP1R** — Glucagon-like peptide 1 receptor. Anti-hyperglycemia. Anti-appetite.
- **GIPR** — Gastric inhibitory peptide receptor. Synergizes with GLP1R on weight loss.
- **GCGR** — Glucagon receptor. Hepatic glucose output, lipid metabolism.

What changes between the approved and emerging GLP-1 drugs is which receptors get hit:

| Drug                | GLP1R | GIPR | GCGR | Indication                                  |
|---------------------|-------|------|------|---------------------------------------------|
| Semaglutide         | ✓     |      |      | T2D, obesity                                |
| Liraglutide         | ✓     |      |      | T2D                                         |
| Tirzepatide         | ✓     | ✓    |      | T2D, obesity (better than sema for weight)  |
| Retatrutide         | ✓     | ✓    | ✓    | MASH, obesity, severe T2D                   |
| Orforglipron (oral) | ✓     |      |      | T2D, obesity (cost-sensitive markets)       |

Retatrutide is the only triple agonist. GCGR is the third receptor — and that's the receptor that's the **liability for T2D** and the **therapeutic for MASH**. Glucagon raises blood sugar (bad for T2D) and burns hepatic fat (good for MASH).

So when someone asks "what's the next GLP-1 for obesity?" the answer might be tirzepatide-class. When they ask "what's the next GLP-1 for MASH?" the answer is retatrutide-class. They're different drugs with different receptor patterns.

## What BioMate does in 4 phases

> 📊 **Figure 1** — `figures/post_20_glp1_bakeoff.drawio.xml` (4-phase block diagram + receptor expression heatmap)

**Phase A — Receptor atlas profile.** Pull GLP1R, GIPR, GCGR tissue expression from Tabula Sapiens. The critical data point: GCGR is hepatocyte-dominant. GLP1R is broadly expressed (pancreas, brainstem, adipose). GIPR is adipose-dominant. The atlas is what makes the indication question answerable.

**Phase B — Modality scoring.** Score 6 candidate modalities — semaglutide-class, liraglutide-class, tirzepatide-class, retatrutide-class, orforglipron-class, novel triple — on 6 axes:
- receptor coverage match
- weight-loss potency
- metabolic-correction potency (HbA1c, lipids, MASH fat)
- safety profile (nausea, hypoglycemia, lipid changes)
- delivery (injection vs. oral)
- IP whitespace (is the receptor pattern already owned?)

**Phase C — Indication weighting.** Apply indication-specific weights:
- **MASH** → GCGR engagement +10 (hepatic fat oxidation); GLP1R-only −5 (insufficient)
- **T2D** → GCGR engagement −10 (glucagon counter-regulates); GLP1R+GIPR is the sweet spot
- **Obesity (BMI <35)** → balanced; semaglutide-class can work
- **Obesity (BMI ≥35)** → tirzepatide-class or retatrutide-class
- **Cost-sensitive (Asia/LMIC)** → orforglipron-class for oral cost advantage

**Phase D — Top recommendation.** Output ranked CSV + rationale + clinical-program comparator citations. For MASH, retatrutide-class wins because GCGR engagement is the therapeutic, not a liability.

## Why this isn't a single-prompt LLM question

Ask ChatGPT "what's the next GLP-1 for MASH?" and it'll mention semaglutide-class, tirzepatide-class, retatrutide-class — and not give you a ranking. It can't.

Because the ranking depends on:

1. The receptor expression heatmap from a single-cell atlas (not in pre-training)
2. The mechanistic weighting (GCGR good for MASH, bad for T2D) — a published consensus, but blended in pre-training with conflicting prior literature
3. The IP whitespace check (Lilly already has retatrutide in Phase III)

BioMate combines all three deterministically:
- Atlas query → live data
- Scoring matrix → canonical, with literature citations
- Indication weights → exposed as overridable parameters

Run the same workflow with `indication=t2d` and the top recommendation flips from retatrutide-class to tirzepatide-class. Same pipeline. Different weights.

## Try it

```
Compare GLP-1 modalities for MASH: semaglutide vs tirzepatide vs retatrutide
```

→ [biomate.ai](https://biomate.ai)

30 seconds. 4 phases. Retatrutide-class returns at the top with a GCGR-engagement rationale.

Switch to `T2D` → tirzepatide-class wins.

Switch to `obesity, cost-sensitive (Indian market)` → orforglipron-class wins because of oral delivery economics.

The question "what's the next GLP-1?" doesn't have one answer. It has six, indexed by indication. BioMate makes the indexing explicit.

---

*Yaoyun Wang is the founder of BioMate, an agentic AI orchestration platform for drug development.*
