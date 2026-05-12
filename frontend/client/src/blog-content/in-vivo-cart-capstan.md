# In vivo CAR-T's hardest problem isn't biology — it's multi-modality co-design

*BioMate Research Team — May 12, 2026*

Ex vivo CAR-T costs $400,000 to $500,000 per patient. The drug itself isn't expensive — the manufacturing is. Leukapheresis, T-cell selection, viral transduction, ex vivo expansion, release testing, lymphodepleting conditioning, reinfusion. Each step costs money. Each step costs time. Each step is a place a patient can die before the cells come back.

In vivo CAR-T eliminates the manufacturing. You inject an LNP carrying mRNA encoding the CAR. The patient's own T cells take up the LNP, translate the CAR, and become CAR-T cells inside the body. Capstan Therapeutics ($165M Series A, 2023), Umoja Biopharma ($122M, 2024), and Kelonia Therapeutics ($115M, 2024) are all racing to do this. First clinical readouts expected 2025–2026.

The biology is hard. The design problem is harder — and it's not what most people think it is.

## The design problem is multi-modality, not single-modality

A traditional CAR-T design is about the construct: scFv binder, hinge, transmembrane domain, costimulatory domain, CD3ζ. That's a solved problem.

An in vivo CAR-T design is three problems stacked:

1. **CAR target selection** — same as ex vivo. Atlas-driven safety check. If the target is on cardiac endothelium (the HER2 lesson, Morgan 2010), reject before you start.
2. **LNP tropism** — which cells does the LNP actually transfect? MC3 goes to hepatocytes (wrong cell type, kills your program). C12-200 with optimized lipid composition is spleen-tropic and accesses splenic T cells. Anti-CD8 antibody-conjugated LNP (Capstan's CPTX-2309) is CD8-T-cell-selective.
3. **Fratricide check** — the trap. If the LNP transfects T cells AND the CAR target is on T cells, the new CAR-T cells kill each other. Worse, they kill the LNP-target population, so the therapy can't expand.

These are not independent decisions. They have to be co-designed.

## The fratricide trap

Consider CD7 CAR-T. CD7 is a T-cell receptor, expressed on essentially all T cells. As an ex vivo CAR-T, this works if you engineer the T cells to be CD7-knocked-out before you transduce them. Allogene and BeBio have done this with B2M-KO + CD7-KO allogeneic platforms.

Now consider in vivo CD7 CAR-T. The natural LNP for T-cell access is anti-CD5 or anti-CD7. Both transfect T cells. Now those T cells translate the CD7 CAR, become CAR-T, and start killing CD7+ cells — which is *every other T cell, including all the other LNP-target cells*. The therapy nukes its own delivery population.

The framework `in_vivo_cart_codesign` flags this in 30 seconds:

```
Phase 3: Fratricide Check
  Risk:        YES
  Rationale:   LNP anti_CD5 transfects T cells. CAR target CD7 is
               expressed on T cells. The newly-generated CAR-T cells
               will kill each other AND the LNP-target T-cell population.
  Mitigation:  Engineer CAR-T to be CD7-KO before transduction
               (electroporation of CRISPR for ex vivo, or co-delivery
               of guide RNA for in vivo). Capstan/Allogene pattern:
               B2M-KO + CD7-KO. Alternatively, switch LNP to anti_CD8
               or change CAR target to a non-T-cell antigen.
```

Without this check, the program enters preclinical, generates ambiguous data, and the team eventually figures out the mechanism by exclusion. Months lost. Tens of millions of dollars lost.

## Why no single-modality platform solves this

Every other bioinformatics platform handles one piece:

- Schrödinger and Insilico do small molecule design. They don't have CAR architecture or LNP tropism.
- Generate Biomedicines and Cyrus do protein design. They don't have LNP tropism or atlas-driven target safety.
- Charm Therapeutics does co-folding. They don't have cell therapy or LNP workflows.
- Cartography Biosciences finds CAR-T targets. They don't ship a design tool to customers.

The required ingredients — atlas coverage + LNP tropism library + CAR architecture rules + fratricide reasoning — only exist together in a multi-modality platform.

## What the workflow does end-to-end

Input: CAR target, indication, delivery cell type, optional LNP preference, optional persistence.

Phase 1 runs atlas safety on the CAR target. Phase 2 selects or scores the LNP from a 7-LNP library (MC3, SM-102, C12-200, anti-CD8, anti-CD5, anti-CD3, anti-CD7). Phase 3 cross-references LNP target cells with CAR target expression to detect fratricide. Phase 4 selects the CAR architecture optimized for transient mRNA (CD28 costimulatory for faster effector response). Phase 5 emits the integrated design report.

Smoke-tested on three cases: CD19 + anti-CD5 LNP (no fratricide, GO), CD7 + anti-CD5 LNP (fratricide, NO-GO with mitigation), BCMA + C12-200 spleen (no fratricide, GO). All three match expected outcomes.

## Honest disclaimers

- RNA expression ≠ surface protein expression. IHC, flow cytometry, or scProteomics validation is required before any clinical decision.
- Atlas reference data is from healthy tissue. Tumor heterogeneity is not captured in this analysis.
- This is decision support for program-design triage, not clinical decision-making. The framework triages programs at design stage, not patients in the clinic.
- In vivo CAR-T is preclinical or Phase 1 frontier. Clinical efficacy is not yet established at scale. LNP tropism profiles are based on published lipid library data; in vivo behavior in patients varies.

## Try the workflow

Run `in_vivo_cart_codesign` on your CAR-T target at [biomate.ai/capabilities](https://biomate.ai/capabilities). The framework returns an integrated design report (atlas + LNP + fratricide + construct) in under 30 seconds.

---

## BioMate is the AI platform for multi-modality drug development

It is the only orchestration layer where single-cell atlas data and every modality's design workflow live in one place — small molecule, antibody, ADC, mRNA, siRNA, ASO, CRISPR, CAR-T, PROTAC, AAV gene therapy. The result: what used to be a 6-week modality-decision committee becomes a 30-second atlas-driven analysis, before $50M of preclinical commitment.

[Capabilities](https://biomate.ai/capabilities) · [Talk to us](https://biomate.ai/contact) · [Technical docs](https://github.com/bioMate-AI/biomate/tree/main/docs)
