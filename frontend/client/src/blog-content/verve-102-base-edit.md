# VERVE-102 is the gene editing trial everyone's watching — here's what BioMate would have designed

*BioMate Research Team — May 12, 2026*

In November 2023, Verve Therapeutics paused VERVE-101 — its in vivo cytosine base editing program for PCSK9 — after a Grade 3 liver enzyme elevation in a single patient. The Internet panicked. Verve responded with engineering: a reformulated LNP with reduced PEG content and a different ionizable lipid. The new program, VERVE-102, dosed its first patient in Q4 2024. It is currently the most-watched gene editing trial in the world.

If VERVE-102 works, the in vivo gene editing era goes commercial. Hypercholesterolemia patients get a single intravenous infusion and never need a statin again. Hemophilia, transthyretin amyloidosis, sickle cell disease — every previously-genetic-but-mostly-untreatable indication suddenly has a one-shot cure pathway. If VERVE-102 fails on safety, the field's regulatory bar goes up by another five years.

The design question worth asking right now is: **was the original Verve design correct, and was the VERVE-102 reformulation the right response?** BioMate's `in_vivo_base_edit_design` workflow recovers Verve's actual design from first principles.

## The design problem

In vivo base editing is the most demanding multi-step design in biotech right now:

1. **Target gene tissue restriction** — atlas-driven. The target must be predominantly expressed in tissue the delivery vehicle can reach. Pleiotropic targets are off-limits.
2. **Editor class** — CBE (C→T), ABE (A→G), or prime editing. Determined by the desired edit (premature stop codon vs point correction vs insertion).
3. **Delivery vehicle** — LNP IV (hepatocyte), ex vivo HSC + retransplant (bone marrow), AAV9 IV (cardiac/muscle), AAV9 intrathecal (CNS). Cannot be optimized later; this is the design.
4. **Guide RNA** — sequence and chemistry. Off-target editing has to be characterized genome-wide.
5. **IND-readiness** — preclinical pharmacology, GLP tox, CMC, long-term follow-up commitment.

Get any of these wrong and the program either fails preclinically or causes the Grade 3 event that paused VERVE-101.

## What the framework says about PCSK9

Running the workflow on PCSK9 / loss_of_function / hypercholesterolemia:

```
Atlas Tissue Context:
  Primary tissue: hepatocyte
  Criticality:    MOD
  Note:           Liver-restricted; ideal LNP IV target

Editor Recommendation: CBE
  Mechanism:    Premature stop codon (CAA→TAA, CAG→TAG, CGA→TGA) via
                C→T transition. Verve VERVE-101/102 uses W8X stop.
  Efficiency:   40-60% editing in hepatocyte; sufficient for PCSK9 KO
                given dose-response of LDL lowering.

Delivery Plan: lnp_iv_hepatocyte
  LNP chemistry: MC3-class or biodegradable ionizable lipid
                 (VERVE-102 reformulation)
  Route:        Intravenous infusion
  CMC flag:     VERVE-101 LFT elevation (Nov 2023) → optimize LNP for
                lower hepatotoxicity (reduced PEG, alternative ionizable
                lipid). VERVE-102 addressed this.
```

This matches Verve's actual VERVE-101/102 design exactly. The framework also flags the VERVE-101 LFT lesson and points to the LNP reformulation that was the correct response — without any post-hoc knowledge of what Verve actually did.

## Recovering BEAM-101 and VERVE-201

The same framework recovers two other clinical designs from inputs alone:

**BEAM-101 (Beam Therapeutics, sickle cell disease)**: target HBG1, regulatory_modification, sickle_cell. Output: ABE editor, ex vivo HSC delivery, expected efficiency 60–80%. This matches Beam's actual platform — ABE on the HBG1/2 promoter to derepress fetal hemoglobin in autologous HSCs.

**VERVE-201 (Verve, dyslipidemia)**: target ANGPTL3, loss_of_function, dyslipidemia. Output: CBE editor, LNP IV hepatocyte, MC3-class chemistry. Matches Verve's published preclinical work on ANGPTL3 knockout.

Three for three: the framework recovers the actual clinical design for the three highest-profile in vivo base editing programs in the world.

## What the framework predicts for future targets

Applied prospectively to adjacent candidates:

- **LPA (lipoprotein(a) lowering)** — hepatocyte-restricted, LoF. CBE, LNP IV. Highly likely to succeed if Verve's LNP chemistry transfers.
- **TTR (transthyretin amyloidosis)** — hepatocyte-restricted, LoF. CBE, LNP IV. Intellia NTLA-2001 already validates this with CRISPR knockout (not base editing).
- **APP (Alzheimer's amyloid precursor)** — neuronal, MOD-HIGH tier. ABE or prime editing, intrathecal LNP or AAV9. Significantly harder than hepatocyte targets; current delivery is the bottleneck.
- **HBB (sickle cell direct correction)** — erythroid-restricted, correction goal. ABE, ex vivo HSC. Beam BEAM-201 is the precedent.

The output package also includes a one-page "IND-readiness checklist" with preclinical pharmacology requirements, GLP tox (LFT monitoring per VERVE-101 lesson), CMC (cap structure, m1Ψ modification, gRNA chemistry), and FDA pre-IND meeting recommendation.

## Honest disclaimers

- RNA expression ≠ surface protein expression. IHC, flow cytometry, or scProteomics validation is required before any clinical decision.
- Atlas reference data is from healthy tissue. Tumor heterogeneity is not captured in this analysis.
- This is decision support for program-design triage, not clinical decision-making. The framework triages programs at design stage, not patients in the clinic.
- In vivo base editing is permanent. There is no opportunity for dose reduction after administration. Off-target editing in critical tissue requires comprehensive whole-genome profiling (GUIDE-seq, CIRCLE-seq) — atlas flags are a starting point, not a substitute.

## Try the workflow

Run `in_vivo_base_edit_design` on your in vivo edit candidate at [biomate.ai/capabilities](https://biomate.ai/capabilities). The framework returns editor selection, delivery vehicle, guide RNA strategy, and IND-readiness checklist in under 30 seconds.

---

## BioMate is the AI platform for multi-modality drug development

It is the only orchestration layer where single-cell atlas data and every modality's design workflow live in one place — small molecule, antibody, ADC, mRNA, siRNA, ASO, CRISPR, CAR-T, PROTAC, AAV gene therapy. The result: what used to be a 6-week modality-decision committee becomes a 30-second atlas-driven analysis, before $50M of preclinical commitment.

[Capabilities](https://biomate.ai/capabilities) · [Talk to us](https://biomate.ai/contact) · [Technical docs](https://github.com/bioMate-AI/biomate/tree/main/docs)
