# LinkedIn feed post — Post 17 (Bispecific Format Triage / Ivonescimab)

**Recommended hero image:** the 4-phase pipeline figure. See `figures/post_17_bispecific_pipeline.drawio.xml` and export as 1200×627 PNG.

**Character count:** ~2,300 / 3,000 limit. First ~210 chars must hook before "See more" truncation.

---

October 2024: Ivonescimab — a PD-1 × VEGF CrossMab from Akeso/Summit — beat pembrolizumab head-to-head in HARMONi-2 NSCLC. First drug ever to beat Keytruda in a Phase III oncology readout.

Why CrossMab and not BiTE or KiH? The answer is biology, not chemistry preference.

Akeso took 18 months and a team of architects to settle on CrossMab.

BioMate recovers the same architectural choice from the two target names — in 30 seconds.

We tested 5 of 5 approved bispecifics:

🔵 PD-1 × VEGF → Ivonescimab (CrossMab) ✓
🔵 CD3 × CD19 → Blinatumomab (BiTE) ✓
🔵 CD3 × BCMA → Teclistamab (KiH) ✓
🔵 HER2 × HER3 → Zenocutuzumab (CrossMab) ✓
🔵 EGFR × MET → Amivantamab (KiH) ✓

5 of 5 architectural choices recovered from inputs alone.

How? 4 phases, all auditable to a JSON file:

1️⃣ Mechanism inference — precedent lookup; CD3 anchor implies T-cell engagement; otherwise cis on shared cell type.

2️⃣ Format scoring matrix — 5 architectures (BiTE / CrossMab / KiH / DVD-Ig / Nanobody) scored 0-5 on 6 axes (half-life, cis, trans, manufacturing, ADA, affinity asymmetry). Canonical, sourced from Labrijn 2019.

3️⃣ Composite ranking — cis-engagement → favor half-life + affinity asymmetry. Trans-engagement → favor manufacturing + low ADA.

4️⃣ Report synthesis — `format_ranking.csv` + precedent-cited summary. Drops into a CMC kickoff doc on day one.

For PD-1 × VEGF (cis on tumor endothelium-T cell interface): CrossMab 100 score, 67%. BiTE 30 because half-life is fatal. KiH 78. CrossMab wins.

This isn't possible in ChatGPT — you'll get a fluent paragraph mentioning "CrossMab and KiH as options." It won't tell you cis-engagement geometry decides it.

In BioMate, every number traces to a JSON file. When CMC asks "why CrossMab?" — `format_ranking.csv: row 1, score 100, weighted by cis_engagement=4`. Not "the AI suggested it."

Open trial — bring two target proteins:

👉 biomate.ai

Full essay (with diagrams): [link to Substack post]

#DrugDiscovery #BispecificAntibodies #AIinPharma #BiotechInnovation #Ivonescimab
