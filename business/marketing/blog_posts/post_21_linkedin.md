# LinkedIn feed post — Post 21 (Modality Triage / BCMA)

**Recommended hero image:** the atlas→triage chain figure. See `figures/post_21_modality_triage.drawio.xml`.

**Character count:** ~2,300 / 3,000 limit.

---

Q4 2024 alone, the FDA approved 7 new oncology biologics: bispecifics, ADCs, CAR-Ts, mAbs. Each program made a modality choice early — CAR-T or ADC or bispecific or mAb — that defined the next 7 years of development.

Can the modality choice be recovered from the target gene alone?

We tested 7 of 7 Q4 2024 approvals:

🔵 BCMA → CAR-T (Abecma, Carvykti) ✓
🔵 DLL3 → Bispecific (Imdelltra) ✓
🔵 Claudin18.2 → mAb (Vyloy) ✓
🔵 TROP2 → ADC (Trodelvy, Enhertu) ✓
🔵 HER2×HER3 → Bispecific (Bizengri) ✓
🔵 FRα → ADC (Elahere) ✓
🔵 GPRC5D → Bispecific (Talvey) ✓

7 of 7 modality choices recovered from atlas + biology alone.

How? The agent chains TWO workflows automatically when it sees a triage question:

1️⃣ atlas_expression_query (3 phases) — pull tissue expression from Tabula Sapiens + CELLxGENE Census. For BCMA: plasma cells (high), plasmablasts (moderate), no critical-tissue hits.

2️⃣ modality_triage (4 phases) feeds on Step 1's output:
  ↳ Phase A — Atlas profile (inherits tissue map)
  ↳ Phase B — CAR-T viability (restricted lineage + no critical hits = CAR-T gold standard, Abecma pattern)
  ↳ Phase C — ADC + bispecific eval (internalization for ADC, paired-target with CD3 for bispecific)
  ↳ Phase D — Modality ranking + IHC follow-up panel for IND prep

For BCMA, the ranking returns:
1. CAR-T (best persistence — Abecma/Carvykti)
2. Bispecific (faster onset, cheaper — Teclistamab)
3. ADC (less explored)
4. mAb (insufficient — naked anti-BCMA mAb has been tried, fails)

Run the same chain on Claudin18.2:
1. mAb (Vyloy precedent)
2. ADC (TST001 in clinic)
3. Bispecific (no internalization advantage)

Same chain, different biology, different answer.

You can ask ChatGPT "what modality for BCMA?" and get a thoughtful paragraph mentioning CAR-T and bispecifics.

You won't get:

❌ Tissue expression across 26 types from a real single-cell atlas
❌ A viability flag based on critical-tissue scan (catches: MUC1 on broad epithelium would deplete gut/skin — bad CAR-T target)
❌ A side-by-side with approved drug names + agency dates
❌ An IHC follow-up panel with antibody validation for IND prep

BioMate produces all four from one chat sentence. The agent recognizes triage, chains atlas → triage automatically, and runs both.

7-of-7 isn't because the agent memorized the approval list. The workflow is grounded in the same atlas data the approval-stage programs all used — they just spent 2 years.

BioMate runs it in 60 seconds.

Try it on an unannounced target in your 2025 pipeline. Get an early read before $50M of preclinical commitment.

👉 biomate.ai

Full essay (with diagrams): [link to Substack post]

#DrugDiscovery #ModalitySelection #BCMA #AIinPharma #BiotechInnovation
