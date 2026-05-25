# LinkedIn feed post — Post 20 (GLP-1 Modality Bakeoff / MASH)

**Recommended hero image:** the 4-phase pipeline + receptor heatmap. See `figures/post_20_glp1_bakeoff.drawio.xml`.

**Character count:** ~2,300 / 3,000 limit.

---

Semaglutide hit $42B in 2024. Tirzepatide hit $36B. Every pharma is asking: what's the next GLP-1?

Wrong question.

The right question is: **what's the next GLP-1 for which indication?**

The GLP-1 family has three receptors:
🔵 GLP1R — anti-hyperglycemia, anti-appetite
🔵 GIPR — synergizes weight loss
🔵 GCGR — hepatic glucose output, lipid metabolism

GCGR is the receptor that flips polarity:
🔄 Liability for T2D (glucagon raises blood sugar)
🔄 Therapeutic for MASH (glucagon burns hepatic fat)

That's why retatrutide (the triple agonist) is the front-runner for MASH but not the first choice for T2D — where tirzepatide-class (GLP1R + GIPR only) wins.

Same chemistry family. Different drug for different patient.

BioMate runs the bakeoff in 4 phases:

1️⃣ Receptor atlas profile — GLP1R/GIPR/GCGR tissue expression from Tabula Sapiens. GCGR is hepatocyte-dominant — that's the data point that decides MASH.

2️⃣ Modality scoring — score 6 candidates (sema/liraglutide/tirz/reta/orforglipron/novel-triple) on 6 axes (receptor match, potency, safety, delivery, IP).

3️⃣ Indication weighting:
  ↳ MASH → GCGR +10 (hepatic fat oxidation)
  ↳ T2D → GCGR −10 (glucagon counter-regulates)
  ↳ Obesity BMI ≥35 → tirz or reta
  ↳ Cost-sensitive → orforglipron (oral economics)

4️⃣ Top recommendation — ranked CSV + rationale + clinical comparator citations.

For MASH: retatrutide-class wins. GCGR engagement is the therapeutic.

Switch to T2D → tirzepatide-class wins.

Switch to "obesity, cost-sensitive, Indian market" → orforglipron-class wins on oral delivery economics.

Same pipeline. Different weights. Different drug.

Why this isn't a single-prompt ChatGPT answer:

❌ Tissue receptor heatmap is not in LLM pre-training
❌ GCGR-good-for-MASH / GCGR-bad-for-T2D consensus is blended with conflicting prior literature
❌ Indication weights aren't exposed as parameters you can override

BioMate does it deterministically. Atlas query → live data. Scoring matrix → canonical with citations. Weights → overridable.

The question "what's the next GLP-1?" doesn't have one answer. It has six, indexed by indication. BioMate makes the indexing explicit.

👉 biomate.ai

Full essay (with diagrams): [link to Substack post]

#GLP1 #DrugDiscovery #MASH #Obesity #AIinPharma #BiotechInnovation
