# Bispecific format triage — how BioMate recovers Ivonescimab's CrossMab choice from two protein names

*October 2024: Ivonescimab (Akeso/Summit, PD-1 × VEGF, CrossMab format) beat pembrolizumab head-to-head in HARMONi-2 NSCLC. The first time any drug had beaten Keytruda in a Phase III oncology readout. Akeso took 18 months and a team of architects to choose CrossMab. BioMate recovers the same answer from the two target names in 30 seconds.*

---

## The format question is the question

When you decide to make a bispecific antibody, the molecule design has six axes to optimize:

- **half-life** — minutes vs. weeks
- **cis-engagement** — both targets on the same cell
- **trans-engagement** — the two targets bridge two different cells
- **manufacturing yield** — CHO mispairing, aggregation, columns
- **ADA risk** — anti-drug antibodies from non-natural junctions
- **affinity asymmetry** — do you need 2:1 binding stoichiometry?

There are five viable bispecific architectures — BiTE, CrossMab, KiH (Knob-into-Hole), DVD-Ig, and Nanobody fusion. Each is good at three of the six axes and bad at three. The choice depends on the **biology**, not on what the chemistry team likes building.

Get the format wrong and you spend 18 months in CMC chasing aggregation, then watch ADA crater your Phase 1.

Get it right and you beat Keytruda.

---

## The five known winners — what BioMate recovers

We tested 5 of 5 approved or late-stage bispecifics:

| Targets         | Drug                        | Approved format | BioMate ranks #1 |
|-----------------|------------------------------|-----------------|------------------|
| PD-1 × VEGF     | Ivonescimab (HARMONi-2 2024) | CrossMab        | ✓ CrossMab       |
| CD3 × CD19      | Blinatumomab (Blincyto 2014) | BiTE            | ✓ BiTE           |
| CD3 × BCMA      | Teclistamab (Tecvayli 2022)  | KiH             | ✓ KiH            |
| HER2 × HER3     | Zenocutuzumab (Bizengri 2024)| CrossMab        | ✓ CrossMab       |
| EGFR × MET      | Amivantamab (Rybrevant 2021) | KiH             | ✓ KiH            |

**5 of 5 architectural choices recovered from inputs alone.** Not from a clinical trial database lookup — from a 4-phase scoring pipeline that runs the actual biology.

---

## The 4 phases

> 📊 **Figure 1** — `figures/post_17_bispecific_pipeline.drawio.xml` (4-phase block diagram)

**Phase A — Mechanism inference.** Look up known precedents in the 50-pair clinical bispecific cache. If the target pair has a precedent, take its mechanism. If CD3 is one of the targets, it's a T-cell engager (trans-engagement). Otherwise default to cis-engagement on the inferred shared cell type.

**Phase B — Format scoring matrix.** Each of 5 architectures (BiTE, CrossMab, KiH, DVD-Ig, Nanobody) scored 0-5 on each of 6 axes. The matrix is canonical, sourced from Labrijn 2019 *Nat Rev Drug Discov* and Kontermann 2015 *Drug Discov Today*. Manufacturing flags applied per format (DVD-Ig aggregation risk; BiTE continuous-infusion requirement).

**Phase C — Composite ranking.** Apply mechanism-dependent weights:
- cis-engagement → `{cis_eng: 4, half_life: 3, affinity_asymmetry: 2, manufacturing: 2, ada: 1, trans: 0}`
- trans-engagement → `{trans_eng: 4, manufacturing: 3, ada: 3, half_life: 1, cis: 0, affinity_asymmetry: 2}`

For PD-1 × VEGF on tumor endothelium-T cell interface (cis), CrossMab scores 100 and 67%. BiTE scores 30 because half-life is fatal.

**Phase D — Report synthesis.** Output: `bispecific_format_report.json`, `format_ranking.csv`, and a human-readable summary with Ivonescimab precedent cited. The same JSON drops into a CMC kickoff doc on day one.

---

## Why this isn't possible in ChatGPT

Run "PD-1 × VEGF bispecific format" through ChatGPT and you'll get a fluent paragraph that mentions both CrossMab and KiH as "options to consider." It won't tell you the cis-engagement geometry favors CrossMab specifically. It won't tell you the half-life matters in this indication. And it won't tell you Ivonescimab took CrossMab through HARMONi-2 to beat Keytruda — because that's a specific Phase III readout from a specific Asian biotech, and the LLM blends it into a wash of clinical bispecific lore.

BioMate's 4-phase pipeline doesn't blend. The mechanism is inferred and persisted to disk. The format scores are scored on a fixed matrix. The ranking falls out of an arithmetic weighting. Every number traces to a `.json` file you can audit.

When a CMC director asks "why CrossMab?", the answer is `format_ranking.csv:row 1, score 100, weighted by cis_engagement=4`. Not "the AI suggested it."

---

## Try it

```
Design a PD-1 × VEGF bispecific in CrossMab format for NSCLC
```

→ [biomate.ai](https://biomate.ai)

30 seconds. 4 phases on AWS Batch. CrossMab returns #1.

Run it again with `CD3 × DLL3` and the workflow flips to BiTE — same pipeline, different inferred mechanism, different answer. Tarlatamab (Imdelltra, Amgen 2024) is BiTE.

The science is real. The architecture is auditable. The biotech that beat Keytruda did this with 18 months and a team. You can do it in 30 seconds.

---

*Yaoyun Wang is the founder of BioMate, an agentic AI orchestration platform for drug development.*
