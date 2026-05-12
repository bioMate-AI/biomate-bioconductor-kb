# Tirzepatide for obesity, retatrutide for MASH: BioMate's GLP-1 bake-off

*BioMate Research Team — May 12, 2026*

GLP-1 is the trillion-dollar drug story of the decade. Semaglutide (Ozempic, Wegovy) and tirzepatide (Mounjaro, Zepbound) have rewritten metabolic disease. Eli Lilly's market capitalization passed $800 billion partly on the strength of one molecule. Novo Nordisk became the most valuable company in Europe. The SELECT trial (2023) showed semaglutide cuts major adverse cardiovascular events by 20% in obese non-diabetics. SURMOUNT-OSA (2024) showed tirzepatide reduces sleep apnea events by 60%. SYNERGY-NASH (2024) showed tirzepatide reverses MASH in over half of treated patients.

Every pharma company in the world is now asking the same question: **what's the next GLP-1?**

The answer depends on the indication. And the answer is now a modality question, not just a molecule question.

## The receptor triangle

GLP-1 belongs to a closely related receptor family of three:

- **GLP1R** — gut L-cells, pancreatic α/β cells, hypothalamic POMC neurons, cardiac muscle at low level, bone osteoblasts, thyroid C cells. Drives insulin secretion, appetite suppression, gastric slowing, well-documented CV benefit.
- **GIPR** — pancreatic β cells, white and brown adipose, bone osteoclasts, hypothalamic neurons. Adds direct effects on adipose; modulates GLP-1 GI side effects. The "GIP arm" of tirzepatide.
- **GCGR** — hepatocytes (primary), pancreatic α cells, kidney tubule, brown adipose. Mobilizes hepatic glucose, promotes fat oxidation. The "glucagon arm" of retatrutide.

Each receptor's expression pattern predicts a different therapeutic profile. The framework `glp1_modality_bakeoff` pulls atlas-level expression for all three and computes indication-specific modality recommendations.

## What the framework recommends per indication

Running on five major indications, the bake-off produces clearly differentiated answers:

```
obesity      → Tirzepatide-class (GLP1R + GIPR)
                  Best balance of efficacy + GI tolerance; SURMOUNT approval
t2d          → Tirzepatide-class (GLP1R + GIPR)
                  Avoids GCGR hyperglycemia risk; SURPASS-3 head-to-head data
mash         → Retatrutide-class (GLP1R + GIPR + GCGR)
                  GCGR adds hepatic fat oxidation; SYNERGY-NASH-style targeting
cv_outcomes  → Tirzepatide-class
                  Class CV benefit established; balanced safety
osa          → Tirzepatide-class
                  SURMOUNT-OSA approval 2024
```

For T2D, the framework specifically penalizes triple agonists because GCGR agonism mobilizes hepatic glucose — the *opposite* of what diabetes treatment requires. This is a real pharmacology constraint that retatrutide manages with careful dose titration but that a less experienced design team might miss.

For MASH, the same GCGR arm becomes an asset: hepatic fat oxidation is the therapeutic mechanism. The framework correctly switches to triple agonist for this indication.

## The modality dimension

Beyond receptor combination, the next-decade race is on delivery and persistence:

| Modality | Example | Status |
|---|---|---|
| Injectable peptide (weekly SC) | Semaglutide, tirzepatide, retatrutide | Approved / Phase 3 |
| Oral small molecule | Orforglipron (Eli Lilly ACHIEVE) | Phase 3 readout 2025 |
| mRNA-encoded GLP-1 | Preclinical | Theoretical |
| AAV gene therapy | None | Theoretical |

Orforglipron is the cost-disruption play. Oral peptide manufacturing is dramatically cheaper than injectable, and a $50/month GLP-1 opens markets that $1,000/month cannot. The catch is potency — small-molecule agonists of peptide receptors have bioavailability ceilings that limit weight loss to the 8–12% range vs 20%+ for injectable peptides.

mRNA-encoded GLP-1 is the bridge: the patient receives an mRNA-LNP injection monthly or quarterly, and the body expresses the agonist endogenously. Manufacturing infrastructure built for COVID vaccines makes the economics attractive. No clinical program disclosed yet.

AAV gene therapy is the moonshot: one infusion, lifetime expression. The risk is irreversibility — if a patient develops hyperglycemia at age 60, you cannot turn off the AAV. Unlikely to be the lead modality this decade.

## What this means for pipeline triage

A pharma CSO with $500M to deploy in metabolic disease should treat this framework as a portfolio allocation tool, not a winner-picker. The realistic 2030 portfolio looks like:

1. **Approved-class peptide** for first-line obesity — Mounjaro, Wegovy, follow-on biosimilars
2. **Triple agonist peptide** for severe obesity / MASH — Retatrutide if it reads out positive
3. **Oral peptide** for cost-sensitive markets — Orforglipron and follow-ons
4. **mRNA-encoded continuous GLP-1** — for compliance-impaired populations
5. **Niche combinations** — GLP-1 + amylin (Novo CagriSema), selective GIPR antagonist + GLP1R agonist

The framework triages this in 30 seconds for any candidate. It does not replace your medicinal chemistry team. It tells them where to focus.

## Honest disclaimers

- RNA expression ≠ surface protein expression. IHC, flow cytometry, or scProteomics validation is required before any clinical decision.
- Atlas reference data is from healthy tissue. Tumor heterogeneity is not captured in this analysis.
- This is decision support for program-design triage, not clinical decision-making. The framework triages programs at design stage, not patients in the clinic.
- Modality recommendation is a triage prior. Actual program choice depends on IP landscape, manufacturing capacity, and regulatory strategy. GLP-1 thyroid C-cell tumor signal is rodent-specific (medullary tumors in rats); not observed in human trials but remains a boxed warning.

## Try the workflow

Run `glp1_modality_bakeoff` at [biomate.ai/capabilities](https://biomate.ai/capabilities) — pass the indication (obesity, t2d, mash, cv_outcomes, osa) and the framework returns receptor-pattern and modality recommendations in under 30 seconds.

---

## BioMate is the AI platform for multi-modality drug development

It is the only orchestration layer where single-cell atlas data and every modality's design workflow live in one place — small molecule, antibody, ADC, mRNA, siRNA, ASO, CRISPR, CAR-T, PROTAC, AAV gene therapy. The result: what used to be a 6-week modality-decision committee becomes a 30-second atlas-driven analysis, before $50M of preclinical commitment.

[Capabilities](https://biomate.ai/capabilities) · [Talk to us](https://biomate.ai/contact) · [Technical docs](https://github.com/bioMate-AI/biomate/tree/main/docs)
