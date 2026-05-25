# In vivo CAR-T co-design — three molecules, one workflow, no fratricide

*Capstan Therapeutics raised $165M in 2023. Umoja raised $210M before that. Kelonia $50M. The pitch is the same: skip ex vivo CAR-T manufacturing, deliver the CAR construct via LNP straight into the patient's T cells. $5 million per dose drops to $500. Hospital infrastructure drops to outpatient. But the hard part isn't the LNP — it's the co-design.*

---

## Why ex vivo CAR-T can't scale

Kymriah (CD19 CAR-T, Novartis 2017) was the first FDA-approved cell therapy. The price tag at launch was $475,000. Per patient. Plus a hospital admission, plus an apheresis center, plus a 14-day manufacturing turnaround during which the patient is bridging chemotherapy.

Seven years later, manufacturing has improved but the model hasn't scaled. There are <15 fully-qualified ex vivo CAR-T sites in the US. The patients who get to them are a fraction of the patients who need them.

In vivo CAR-T fixes the bottleneck by removing the bottleneck. LNP encapsulates the CAR mRNA + a T-cell-specific surface targeter (anti-CD8, anti-CD3, anti-CD5). The patient gets an IV infusion. The LNP transfects their T cells in vivo. The T cells express the CAR, kill the tumor, and persist as memory cells. No apheresis. No manufacturing. No 14-day window.

## The three things that have to agree

But three molecules now have to be co-designed, not one:

1. **The CAR target** (e.g., CD19 for B-cell lymphoma)
2. **The LNP surface targeter** (e.g., anti-CD8 for T-cell-specific delivery)
3. **The CAR construct itself** (scFv + hinge + transmembrane + costim + CD3ζ)

The hardest failure mode is **fratricide**. If you pick CD7 as your CAR target and anti-CD7 as your LNP targeter, the LNP transfects T cells, the T cells express anti-CD7 CAR, and the CAR-expressing T cells kill each other. The product self-destructs.

The 2024 oncology pipeline is full of programs that should have flagged fratricide earlier and didn't.

## What BioMate does in 4 phases

> 📊 **Figure 1** — `figures/post_18_invivo_cart_pipeline.drawio.xml` (4-phase block diagram)

**Phase A — Atlas safety check.** Query the CAR target across 26 tissue types from Tabula Sapiens + CELLxGENE Census. CD19 is B-cell restricted with no critical-tissue hits → VIABLE for elimination. CD19 → B-cell aplasia (manageable). vs. EGFR → epithelial expression everywhere (NOT VIABLE without selectivity engineering).

**Phase B — LNP tropism selection.** Pick an anti-CD3, anti-CD8, anti-CD5, or anti-CD7 targeting moiety. Characterize the cell set transfected. Anti-CD8 → CD8+ T cells only. Anti-CD5 → all T cells (CD4 and CD8) and a fraction of B cells.

**Phase C — Fratricide check.** Cross the CAR target (Phase A) against the LNP-transfected cell set (Phase B). If overlap → fratricide warning. CD19 CAR + anti-CD8 LNP → no overlap (CD19 is B-cell, CD8 is T-cell) → SAFE.

**Phase D — CAR construct assembly.** Emit the CAR architecture as FASTA. For CD19: FMC63 scFv + CD8α hinge/TM + CD28 costim + CD3ζ — exactly Kymriah's architecture, 1,485 amino acids. With CD7 target, the same workflow would emit a fratricide error and refuse to assemble.

## The Capstan question

Capstan's lead program (CPTX2309) is anti-CD19 mRNA delivered by an anti-CD8 LNP for systemic lupus erythematosus. The Phase 1 readout is expected late 2025.

Run BioMate on the Capstan thesis and the 4-phase pipeline reproduces it: CD19 safe to eliminate, anti-CD8 LNP delivers to CD8 T cells, no fratricide, FMC63-based construct.

The agent doesn't know about Capstan's IND. It infers the design from the biology.

## Why "ChatGPT can do this" is wrong

You can ask ChatGPT to "design an in vivo CAR-T for CD19 lymphoma with anti-CD8 LNP delivery" and it will produce a fluent answer that mentions FMC63, CD3ζ, and anti-CD8 LNPs. What it won't do:

- Check the CAR target's tissue expression against an actual atlas
- Flag the fratricide risk if you swap CD19 for CD5 or CD7
- Emit a FASTA sequence with the correct domain order
- Cite the precedent (Kymriah architecture, Capstan IND)

BioMate's pipeline does all four, and persists each one to a file you can audit. When the IND submission asks "why anti-CD8 LNP and not anti-CD3?" — `lnp_tropism.json` has the cell-set analysis. Not the agent's opinion.

## Try it

```
In vivo CAR-T for CD19 B-cell lymphoma with anti-CD8 LNP delivery
```

→ [biomate.ai](https://biomate.ai)

Swap CD19 → CD7 and watch the fratricide warning fire. Swap anti-CD8 → anti-CD3 and the cell set widens (CD4 T cells join, B cells leave). The pipeline propagates the change through all 4 phases. The final FASTA changes accordingly.

The biotechs with $400M of funding are running this co-design with spreadsheets, slide decks, and a four-month cycle. The cycle should be 30 seconds.

---

*Yaoyun Wang is the founder of BioMate, an agentic AI orchestration platform for drug development.*
