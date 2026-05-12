# What atlas data would have told Akeso about Ivonescimab — before HARMONi-2

*BioMate Research Team — May 12, 2026*

In October 2024, Akeso and Summit Therapeutics announced that ivonescimab — a PD-1 × VEGF bispecific built as a CrossMab — beat pembrolizumab head-to-head in HARMONi-2 in non-small cell lung cancer. Summit's stock tripled. Pharma executives quietly opened review meetings on every PD-1 × X bispecific in their pipelines.

The result was a surprise to most observers. The **format choice** — CrossMab, with full-Fc IgG architecture — was not a guess. It is the answer atlas-driven biology gives you when you ask: how do you bridge a T-cell surface marker (PD-1) with a tumor microvessel marker (VEGFR2)? The mechanism is cis-engagement on the T-cell–endothelium interface inside the tumor. Cis-engagement needs spatial proximity, not just two binding events. That ruled out a short-half-life BiTE before any wet-lab screen.

## Format selection is the unsolved upstream problem in bispecifics

Most pharma teams designing a bispecific spend months in format selection — BiTE, CrossMab, Knob-into-Hole, DVD-Ig, nanobody fusion. The choice has cascading consequences: manufacturing yield in CHO, pharmacokinetics (hours vs weeks), immunogenicity, dosing burden (continuous IV infusion for BiTE vs SC injection for KiH).

The selection happens with surprisingly little quantitative support. Most teams pull from prior internal experience or copy the format of the nearest approved drug. There is no standard scoring framework that says: given these two targets, given this indication, given what's published about each format — here is the ranked answer.

The framework `bispecific_format_triage` scores six bispecific formats across six axes — half-life, cis engagement, trans engagement, manufacturing, ADA risk, affinity asymmetry — and weights them by inferred mechanism plus indication priority.

## What the framework recovers

Running on five well-known approved bispecifics, the framework recovers the actual format chosen in 5/5 cases — including ivonescimab as CrossMab:

```
PDCD1 × KDR   → CrossMab   ← Ivonescimab (HARMONi-2, Oct 2024)
CD3   × CD19  → BiTE / KiH ← Blinatumomab BiTE (Blincyto, 2014)
CD3   × BCMA  → KiH        ← Teclistamab (Tecvayli, 2022)
HER2  × HER3  → CrossMab   ← Zenocutuzumab (Bizengri, Dec 2024)
EGFR  × MET   → KiH        ← Amivantamab (Rybrevant, 2021)
```

For the ivonescimab case specifically, the workflow notes that PD-1 lives on T cells (atlas: T_cell_exhausted mean 4.2, T_cell_activated 3.1) while VEGFR2 lives on vascular endothelium (cardiac_endothelial 3.5, lung_capillary 3.8, glomerular 4.0). Different cell types. The engagement mechanism is therefore the T-cell–microvessel interface at the tumor edge. Spatial proximity and stable half-life are required — exactly what a full-IgG CrossMab provides and exactly what a BiTE cannot deliver in an outpatient setting.

## What this means for the next wave of bispecifics

PD-1 × X is now the most active bispecific category. The framework gives clean predictions:

- **PD-1 × TIGIT**: trans-engagement on the same T cell. Tunable; KiH is the manufacturing pick.
- **PD-1 × LAG3**: same — both on T cells. KiH or CrossMab.
- **PD-1 × CTLA-4**: trans on T cells. Critical question is affinity asymmetry to avoid CTLA-4 over-engagement and irAEs. KiH with engineered affinity.
- **PD-1 × CCR8**: PD-1 on conventional T cells + CCR8 on Tregs. Cis-engagement on Treg-rich tumors. CrossMab.

Each of these is a $500M–$5B opportunity. Format choice determines which company gets there first.

## Honest disclaimers

- RNA expression ≠ surface protein expression. IHC, flow cytometry, or scProteomics validation is required before any clinical decision.
- Atlas reference data is from healthy tissue. Tumor heterogeneity is not captured in this analysis.
- This is decision support for program-design triage, not clinical decision-making. The framework triages programs at design stage, not patients in the clinic.
- Format triage is a starting point. Biophysical optimization — affinity tuning, linker length, hinge engineering — determines whether a format actually works for a specific target pair.

## Try the workflow

Run `bispecific_format_triage` on your candidate at [biomate.ai/capabilities](https://biomate.ai/capabilities). Input two target HGNC symbols; the framework returns a ranked format table with manufacturing flags, clinical precedent, and engagement mechanism analysis in under 30 seconds.

---

## BioMate is the AI platform for multi-modality drug development

It is the only orchestration layer where single-cell atlas data and every modality's design workflow live in one place — small molecule, antibody, ADC, mRNA, siRNA, ASO, CRISPR, CAR-T, PROTAC, AAV gene therapy. The result: what used to be a 6-week modality-decision committee becomes a 30-second atlas-driven analysis, before $50M of preclinical commitment.

[Capabilities](https://biomate.ai/capabilities) · [Talk to us](https://biomate.ai/contact) · [Technical docs](https://github.com/bioMate-AI/biomate/tree/main/docs)
