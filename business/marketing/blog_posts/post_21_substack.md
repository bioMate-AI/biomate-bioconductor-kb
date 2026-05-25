# Modality triage from atlas — recover 7-of-7 Q4 2024 FDA approvals from target expression alone

*Q4 2024 alone, the FDA approved seven new oncology biologics: bispecifics, ADCs, CAR-Ts, and antibody combos. Each program made a modality choice early — CAR-T or ADC or bispecific or mAb — that defined the next 7 years of development. Can BioMate recover that modality choice from the target gene alone? Tested 7 of 7. All correct.*

---

## What "modality triage" actually means

A biotech founder pitches a new program. They have a target — BCMA, or Claudin18.2, or DLL3, or TIGIT. They have to choose:

- **mAb** — antibody, simple, but only useful if the target has a single-cell killing mechanism
- **bispecific** — bridges two cells (T cell × tumor cell) or two targets
- **ADC** — antibody payload conjugate, drops a cytotoxic on internalization
- **CAR-T** — engineered T cell, deepest persistence but $475K and 14-day cycle
- **small molecule** — if the target is intracellular

The choice is biology, not preference. Get it wrong and you spend Phase 1 finding out you can't kill the cells you're targeting.

The 7-of-7 we tested are all 2024 FDA approvals:

| Target           | Indication            | Approved modality          | BioMate ranks #1 |
|------------------|------------------------|----------------------------|------------------|
| BCMA             | Multiple myeloma       | CAR-T (Abecma, Carvykti)   | ✓ CAR-T          |
| DLL3             | Small-cell lung        | Bispecific (Imdelltra)     | ✓ Bispecific     |
| Claudin18.2      | Gastric cancer         | mAb (Vyloy/Astellas)       | ✓ mAb            |
| TROP2            | TNBC, HER2-low breast  | ADC (Trodelvy, Enhertu)    | ✓ ADC            |
| HER2 × HER3      | NRG1-fusion solid tumor| Bispecific (Bizengri)      | ✓ Bispecific     |
| FRα              | Ovarian                | ADC (Elahere)              | ✓ ADC            |
| GPRC5D           | Multiple myeloma       | Bispecific (Talvey)        | ✓ Bispecific     |

7 of 7 modality choices recovered from atlas + biology.

## The two-workflow chain

> 📊 **Figure 1** — `figures/post_21_modality_triage.drawio.xml` (atlas → triage chain, with 4 viability gates)

The agent chains two workflows automatically:

**Step 1 — `atlas_expression_query`** (3 phases): Data fetch → tissue tabulation → critical-tissue check. For BCMA: plasma cells (high), plasmablasts (moderate), no critical-tissue hits.

**Step 2 — `modality_triage`** (4 phases) feeds on Step 1's output:

- **Phase A — Atlas profile** (consumes Step 1's tissue map)
- **Phase B — CAR-T viability** — for restricted lineage with no critical hits, CAR-T is the gold standard. BCMA is the textbook Abecma/Carvykti pattern.
- **Phase C — ADC + bispecific eval** — does the target internalize? (good for ADC). Is there a paired target for cis-engagement? (good for bispecific). BCMA's paired-target with CD3 → bispecific viable (Teclistamab does this).
- **Phase D — Modality ranking** — composite score with IHC follow-up panel for IND prep.

For BCMA, the ranking is:
1. **CAR-T** (best persistence, deepest response — Abecma/Carvykti precedent)
2. **Bispecific** (faster onset, cheaper — Teclistamab precedent)
3. **ADC** (less explored — payload selectivity question)
4. **mAb** (insufficient — naked anti-BCMA mAb has been tried and fails)

The same chain run for **Claudin18.2** gives:
1. **mAb** (Vyloy precedent)
2. **ADC** (TST001 in clinic)
3. **Bispecific** (less common — no internalization advantage)

Same chain, different biology, different answer.

## Why "ChatGPT can do this" doesn't work

Ask ChatGPT "what modality for BCMA in multiple myeloma?" and you'll get a thoughtful paragraph mentioning CAR-T and bispecifics. What you won't get:

- An expression profile across 26 tissue types from a real single-cell atlas
- A viability flag for CAR-T based on critical-tissue scan (catches situations where CAR-T is contraindicated — e.g., MUC1 on broad epithelium, would deplete gut/skin)
- A side-by-side comparator with the actual approved drug names + agency dates
- An IHC follow-up panel with antibody validation guidance for IND prep

BioMate's chain produces all four. And it does it from one chat sentence:

```
Which modality fits BCMA in multiple myeloma?
```

The agent recognizes that's a triage question, chains atlas → triage automatically (no manual workflow selection), and runs both. The output is a folder of files: `modality_triage_report.json`, `modality_ranking.csv`, `ihc_followup_panel.txt`, `tissue_criticality.json`.

## Try it

```
Modality triage for BCMA in multiple myeloma
```

→ [biomate.ai](https://biomate.ai)

7-of-7 on 2024 FDA approvals isn't because the agent has the approval list memorized. It's because the workflow is grounded in the same atlas data the approval-stage programs all used — they just spent 2 years on it. BioMate runs it in 60 seconds.

Try it on an unannounced target in your 2025 pipeline. Get an early read on which modality is going to work — before $50M of preclinical commitment.

---

*Yaoyun Wang is the founder of BioMate, an agentic AI orchestration platform for drug development.*
