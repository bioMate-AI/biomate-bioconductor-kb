# Fixed-Role Committee Review — Reverse-Decomposition Query Generation

**Date:** 2026-10-08
**Author:** Yaoyun Zhang (with Claude Opus 4.8)
**Scope:** Realism / practicality audit of the TRAIN queries produced by
`evaluation/datasets/reverse_decomp/build_reverse_decomp.py`
(`GEN_SYS` + `_cell_instructions`), judged against the design doc
`20261008_REVERSE_DECOMP_DATASET.md`, a stratified sample of the 534 kept TRAIN rows
(`reverse_decomp_train.ok.jsonl`), the 300 real held-out queries
(`reverse_decomp_test_real.jsonl`), and the user's real-voice example
("run all the peptide-property tools on these designed peptides and shortlist 5 for validation").
**Mode:** CPU / static analysis only. No deploys, no app run.

> **Concern under review (user):** do the generated queries reflect *daily, practical
> bioinformatics-workbench* use — or are they a sanitized synthetic voice?

---

## 0. Evidence base (measured, not asserted)

All figures computed directly from the two shipped JSONL files (534 TRAIN kept, 300 TEST real).

| Metric | TRAIN (generated) | TEST (real `example_queries`) |
|---|---|---|
| Query length (chars): median / mean / max | **195 / 265 / 1117** | **45 / 46 / 92** |
| Fraction within the real length band (≤92 chars) | **19%** | 100% |
| Clearly **truncated** mid-sentence / mid-word queries | **84 / 534 = 16%** (min len **4 chars**) | 0% |
| Round-trip `overspec_ratio` (recovered caps ÷ gold core): median / ≥3 / ≥5 | **3.5 / 68% / 31%** | n/a |
| Queries that **name a tool/method/jargon token** | **0%** (hard leak-filter) | **37 / 300 = 12%** |
| Dominant opener | EN "I have / I've got" **~50%**; ZH "我手上有…" **46%** | heterogeneous headline fragments |
| Domains present | even grid; **no** pharmacology, population-genetics, multi-omics, cryo-EM, rare-disease, immuno-oncology | long exotic tail incl. all of those |

These seven numbers drive every finding below.

---

## 1. Bench biologist (wet-lab, low computational jargon)

**Verdict: the queries are too clean, too complete, and over-planned for a real wet-lab voice.**

A real bench scientist sends a *short, partial-knowledge* request and lets the analyst fill gaps.
The generated `lay`/`verbose_postdoc` rows instead read like a methods section written backwards —
they pre-enumerate the entire pipeline, the thresholds, the sample design, and the downstream
intent in one fluent paragraph.

- Over-complete example (rev row, `verbose_postdoc`, metagenomics, 9× overspec):
  > *"I have metagenomic shotgun sequencing data from 18 human gut samples … paired-end FASTQ files,
  > roughly 8 GB each. We need to understand the microbial community composition … which bacteria,
  > archaea, and potentially fungi are present and at what relative abundances … a comprehensive
  > profile that breaks down the taxonomic makeup from phylum down to species level … so we can then
  > assess how the intervention shifted the microbiome … correlate with metabolomic endpoints and
  > clinical readouts downstream."*

  No bench biologist volunteers phylum-to-species resolution, GB-per-file, and the downstream
  correlation plan unprompted. Real voice (TEST): **"scRNA-seq QC normalisation clustering"** /
  **"codon optimization for mRNA vaccine."**

- The **messiness is missing**: no typos, no "I think it's paired-end?", no "the core gave me some
  BAMs, not sure which genome", no "can you just tell me if this is even worth analysing". Every
  generated query knows exactly what it has and what it wants.

**Severity-ranked findings**
1. **[High]** Unnatural completeness — queries state the full design + deliverable + downstream plan; real wet-lab asks are fragments with gaps.
2. **[High]** No partial knowledge / uncertainty / hedging ever appears.
3. **[Medium]** Thresholds quoted too fluently (`FDR<0.05`, `1.5-fold`, `minimum contig 500 bp`) — realistic in ~1 in 5 asks, here in most `explicit_params` rows.
4. **[Low]** The `lay` persona still produces grammatically perfect, well-punctuated prose — not how a rushed biologist types into a chat box.

---

## 2. Bioinformatics-core director (sees real user tickets daily)

**Verdict: the register and the distribution both diverge from a real ticket queue.**

Real core tickets are **headline-length** ("Bulk RNA-seq DE analysis with GO enrichment",
"liftover hg19 to hg38", "defensible pathway analysis for publication"), and the queue is a
**power-law**: RNA-seq-DE and standard scRNA dominate, with a long exotic tail. The generated set
inverts both properties.

- **Length:** TRAIN median **195 chars** vs real **45**; only **19%** of TRAIN falls inside the
  real length band. The generator writes essays; the queue writes subject lines.
- **Distribution:** the diversity GRID samples uniformly, so the TRAIN domain mix is an artificial
  even grid. It contains **no** rows for pharmacology, population genetics, multi-omics integration,
  cryo-EM, rare-disease workups, immuno-oncology, microarray, or CyTOF — all of which are present in
  the 300 real queries (e.g. *"mass cytometry CyTOF analysis"*, *"compare RMA vsn lumi normalization
  microarray"*, *"Should BCMA be CAR-T, ADC, or bispecific"*, *"rtracklayer liftover"*).
- **Under-represented:** the plain, boring, high-frequency ask — *"Bulk RNA-seq DE analysis with GO
  enrichment"* — is drowned by elaborate multi-domain integration essays that are rare in real life.
- **Over-represented:** the `negation_constraint` axis forces **35%** of rows to carry a constraint,
  and the injected constraint recurs verbatim ("不要用任何商业收费的方法" / "skip any commercial
  annotation services"). A real queue almost never says "don't use a paid method."

**Severity-ranked findings**
1. **[Critical]** Length/register mismatch — 81% of TRAIN is longer than the longest real query.
2. **[High]** Even-grid distribution does not match the real RNA-seq-heavy power-law + exotic tail.
3. **[High]** Whole real domains (pharmacology, pop-gen, multi-omics, cryo-EM, microarray, CyTOF, rare-disease) are absent from TRAIN.
4. **[Medium]** "No paid/commercial tool" negation is a synthetic injection that rarely appears in real tickets, yet is in 35% of rows.

---

## 3. Pharma / industry analyst

**Verdict: partially credible. The ADMET/triage asks read right; the "build a QSAR model in the same breath" combos do not.**

- **Credible (keep this voice):**
  > *"I've got a shortlist of twelve lead compounds from our HTS campaign and need ADMET profiles on
  > all of them to triage before moving into in vivo PK studies—can you generate the full property
  > table?"*

  This is exactly how a DMPK/med-chem scientist frames a triage ask, and it matches the user's own
  peptide example in register ("shortlist 5 for validation").
- **Less credible:** the `admet_prediction ∥ qsar_modeling → select` multidomain template produces
  > *"I need pharmacokinetic and toxicity profiles for my hit compounds, then build a predictive
  > model correlating structure to oral [bioavailability]…"*

  In practice ADMET screening and bespoke QSAR model-building are **separate projects on separate
  timelines**; bundling "predict ADMET **and** train a SAR model **and** shortlist" into one chat is
  a synthetic combination driven by the `MULTI_DOMAIN` table, not an industry workflow.
- The real TEST captures genuine industry decision-asks the TRAIN set never reaches:
  *"ADMET screen → CiPA Tier 2 escalation for IND"*, *"GLP-1 bake-off for fatty liver"*,
  *"Triple agonist for MASH design"*. These are **decision-framed** and terse; TRAIN's drug rows are
  **method-framed** and verbose.
- Many drug rows reference `SMILES`/`SDF`/`PDB`/`UniProt` inputs correctly, which is good industry
  grounding — but several are **truncated** exactly at the compound count or target name (e.g.
  "I have a library of 87 small-molecule compounds as SDF files and a crystal structure of our
  target kin[ase]" cuts off), which no analyst would send.

**Severity-ranked findings**
1. **[High]** Synthetic ADMET+QSAR+select bundles don't match how industry phases these as separate asks.
2. **[Medium]** TRAIN drug asks are method-framed; real industry asks are decision/milestone-framed (IND, bake-off, escalation).
3. **[Medium]** Truncation lands on the load-bearing noun (compound count, target), destroying the few otherwise-credible rows.

---

## 4. Realism-skeptic / data auditor

**Verdict: multiple hard synthetic fingerprints, plus a broken round-trip validator that passed obviously-defective rows.**

- **[CRITICAL] 16% of kept rows are truncated fragments.** 84/534 end mid-sentence or mid-word;
  the shortest kept query is **4 characters**. Concrete kept examples:
  > `rev_category_111` → **"Identify pept"** (roundtrip_recall = **1.0**)
  > `rev_single_49` → **"I need predicted binding poses for the top"**
  > `rev_single_81` → **"Generate the three-dimensional structure for the"**
  > `rev_multi_domain_279` → **"…small-molecule candidates … and a crystal structure of our target kin"**

  That these carry `status:"ok"` and often `roundtrip_recall:1.0` proves the **round-trip validator
  is blind to truncation**: it recovers the gold capability from a stub because the gold topic word
  ("peptide", "docking") survives in the fragment. The realism discriminator also failed to flag
  them. This is the single most damaging defect — one in six TRAIN rows is not a query at all.
- **[High] Single-generator voice fingerprint.** ~50% of EN rows open with "I have / I've got …";
  **46%** of ZH rows open with the identical "我手上有…" possessive-data frame. Real queries open
  heterogeneously (imperative, noun-phrase headline, question, tool name). A classifier could
  separate TRAIN from TEST on the opener alone.
- **[High] Over-completeness is measurable, not impressionistic.** Median `overspec_ratio` = **3.5**
  (the query implies 3.5× more capabilities than the gold core); **68%** of rows are ≥3×, **31%** are
  ≥5×, one hits **20×**. This is precisely the "over-complete laundry list / unnatural completeness"
  that `REALISM_SYS` was written to reject — yet only 37 rows were dropped as SYNTHETIC. The
  discriminator is too lax.
- **[Medium] Even-grid ≠ real skew.** `count=multi_task` is forced to ~50% and `negation_constraint`
  to ~35% by uniform grid sampling; neither frequency matches a real queue.
- **[Medium] ZH idiomaticity:** the Chinese is grammatical and reasonably idiomatic
  ("麻烦尽快给我两个结果表格", "我手头有…"), better than a literal calque — but the formulaic
  "我手上有[N]个…" opener and the recurring "不要用任何商业收费的方法" injection are themselves
  the tell, not the grammar.
- **[Low] Textbook tone:** no elision, no sentence fragments, no lowercase-i, no trailing "thx" —
  the exact absence `REALISM_SYS` lists as a synthetic signature.

**Severity-ranked findings**
1. **[Critical]** 16% truncated/stub rows kept; round-trip validator recovers gold from stubs → false "ok".
2. **[High]** Single-generator opener fingerprint (EN ~50% "I have", ZH 46% "我手上有").
3. **[High]** Measured over-completeness (overspec median 3.5) the realism filter fails to catch.
4. **[Medium]** Grid-forced multi_task/negation frequencies and recurring negation phrasing.

---

## 5. Decomposition-task expert

**Verdict: the queries under-exercise real decomposition — and the round-trip filter actively selects *against* the hard cases.**

The whole point of a decomposition benchmark is that the planner must **resolve under-specification**:
map a vague goal to a fan-out/aggregate/select DAG the user never spelled out.

- **The keep-filter inverts this.** A row is kept only if a planner can recover ≥0.5 of the gold
  capabilities **from the query alone** (`_roles_recovered`). This systematically **discards
  under-specified queries** (which score low recall) and **keeps queries that already restate the
  pipeline** — the opposite of what a decomposition set should select for. The kept set is biased
  toward near-1:1 restatements of the gold units.
- Compare the real TEST, which is full of genuinely under-specified asks the planner must unfold:
  > *"defensible pathway analysis for publication"* → gold = primary_processing → per-method DE →
  > consensus GSA (3 units, **none named**).
  > *"Should BCMA be CAR-T, ADC, or bispecific"* → atlas_profile ∥ tier0_drug_design_pipeline.
  > *"Triple agonist for MASH design"* → a full design pipeline from four words.

  No TRAIN row demands this much inference; the generator was told to "state the GOAL … and the
  deliverable", which yields goals that already enumerate the steps.
- **Aggregation is present but shallow.** The `select/rank/integrate` rows do exercise fan-in
  ("shortlist the top five that win on both"), which is genuine and worth keeping. But the two
  branches are almost always the **same two templates** (`admet ∥ qsar`, `germline ∥ DE`), so the
  planner learns two fixed shapes, not general fan-in.
- **Linear chains are mostly QC→align→call**, i.e. the obligatory-prefix pattern. The `read_qc`
  unit is explicitly excluded from the recall check, so these reduce to 1–2 real decisions.

**Severity-ranked findings**
1. **[Critical]** The rt≥0.5 keep-filter selects *against* under-specification — the core skill being benchmarked.
2. **[High]** Queries restate the pipeline (goal = enumerated steps); little latent structure for the planner to infer.
3. **[Medium]** Aggregation fan-in uses only ~4 fixed template pairs → shape memorisation risk.
4. **[Low]** Linear chains collapse to 1–2 real steps once implicit QC is removed.

---

## 6. Committee synthesis

### Verdict: **PARTIALLY** representative — leaning **NO for the TRAIN queries as written.**

The **scaffold is sound and genuinely novel**: reverse direction, real accept-sets, need-satisfaction
grading, a *real* held-out test, proven zero capability-combo overlap. Those are keepers and the
design doc is honest about the local-DB stub limitation.

But the **generated TRAIN queries themselves are not representative of daily practical workbench
use.** They are, on measured evidence: 4× too long (median 195 vs 45 chars), over-complete
(overspec median 3.5×), written in a single-generator voice (~50% "I have…"), stripped of the
tool-naming style that 12% of real queries use, missing the real exotic domain tail entirely, and —
most seriously — **16% are truncated stubs that the round-trip validator rubber-stamped as "ok".**
The real TEST set is the correct target voice; the TRAIN set does not sound like it.

### Cross-role top findings

| Severity | Finding | Roles |
|---|---|---|
| **Critical** | 16% (84/534) truncated/stub queries kept (min 4 chars); round-trip validator recovers gold from stubs → false "ok" | Auditor, all |
| **Critical** | Keep-filter (rt≥0.5) selects *against* under-specification — the decomposition skill the set exists to test | Decomp expert |
| **Critical** | Length/register mismatch: TRAIN median 195 vs real 45 chars; only 19% in real band | Core director |
| **High** | Over-completeness (overspec median 3.5×, 31% ≥5×) — the "laundry list" synthetic tell the realism filter misses | Auditor, bench |
| **High** | Single-generator opener fingerprint (EN ~50% "I have", ZH 46% "我手上有") | Auditor |
| **High** | Even-grid distribution ≠ real power-law; whole real domains absent (pharmacology, pop-gen, multi-omics, cryo-EM, microarray, CyTOF) | Core director |
| **High** | Hard leak-filter bans tool names, but 12% of real queries name tools → a real style is categorically excluded | Core director, auditor |
| **High** | Synthetic ADMET+QSAR+select bundles don't match industry phasing | Pharma |
| **Medium** | "No paid/commercial tool" negation injected into 35% of rows; rare in reality | Core director, pharma |
| **Medium** | Decision/milestone-framed real asks (IND, bake-off, escalation) absent; TRAIN is method-framed | Pharma |

### MUST-FIX guideline changes (top 5, concrete)

1. **Add a hard output validator and REGENERATE the 16% truncated rows.** Reject any query that (a)
   ends without terminal punctuation on a dangling function word / mid-token, (b) is < ~25 chars EN
   / < ~12 chars ZH, or (c) has `finish_reason != "stop"`. Do **not** keep a row the round-trip
   "recovers" if the text is a stub. Raise `max_tokens` is not the fix — the stubs are far under
   budget; log and re-call on `length`/empty `finish_reason`. *(Fixes Critical #1.)*

2. **Re-weight the grid to the real distribution and target the real length band.** Replace uniform
   grid sampling with sampling proportional to the TEST domain histogram (RNA-seq-DE heavy + the
   exotic tail), cap `multi_task` and `negation_constraint` to realistic minorities (≈15% each), and
   add an explicit **length target per persona** so the median lands near 45–90 chars (terse
   headline) for most rows, reserving long paragraphs for a small `verbose_postdoc` minority.
   *(Fixes Critical #3, High distribution.)*

3. **Make the round-trip keep-filter stop penalising under-specification.** Keep (not drop) rows
   where the planner recovers *fewer* capabilities than the gold — those are the valuable
   latent-structure cases. Replace the rt≥0.5 **gate** with: gate only on leak + truncation +
   test-dedup; record rt-recall as a *stratifier*, and deliberately **oversample low-rt
   (under-specified) rows** so the set trains inference, not restatement. *(Fixes Critical #2.)*

4. **Tighten the realism discriminator into an over-completeness + register filter, and relax the
   tool-name ban.** Reject on measured `overspec_ratio ≥ ~4` and on the "I have … then … and finally
   …" enumerated-pipeline shape; stop treating a named tool as an automatic leak — allow a **~12%
   quota** of tool-naming queries to match the real `example_queries` style (keep the ban only for
   the "pure need" subset you explicitly want). *(Fixes High over-completeness + leak-filter
   mismatch.)*

5. **Multi-generator + real-seed harvest to kill the single-voice fingerprint.** Generate across ≥3
   models/temperatures and forbid a fixed opener (ban "I have/I've got/我手上有" as the first clause
   for >X% of rows); **expand the few-shot real seeds beyond style-only** by actually paraphrasing
   the 300 `example_queries` + GTN goal statements into near-real TRAIN rows (the design doc already
   flags the enriched dev/S3 DB as the top lever — prioritise it). Add decision/milestone-framed
   drug asks and the absent exotic domains explicitly. *(Fixes High fingerprint, High missing
   domains, Medium framing.)*

### Patterns to DROP vs KEEP

**DROP**
- Any truncated / stub row (16% of the set) — not negotiable; they are not queries.
- The "I have X … then Y … and finally interpret Z, giving me a ranked list …" over-complete essay
  (overspec ≥5×) — it restates the whole pipeline and reads as a methods section.
- The synthetic `admet ∥ qsar → select` template bundle and the recurring "no paid/commercial method"
  negation injection — both are generator artifacts, not real asks.

**KEEP**
- Concrete, terse, single-goal asks with one real constraint and a clear deliverable
  (e.g. the twelve-lead ADMET triage, the *B. subtilis* QC+assembly, the CD4+ T-cell ChIP
  peak-rank) — these match the user's real example and the TEST register.
- Genuine fan-in/aggregation asks ("shortlist the top five that win on both") — real decomposition
  value; just diversify the branch templates.
- Idiomatic ZH rows that are NOT stub/formulaic (the grammar is good) — fix the opener, keep the
  language coverage.

### Three example queries to CUT

1. `rev_category_111` — **"Identify pept"** — a 13-char truncation stub passed with roundtrip_recall 1.0.
2. `rev_single_49` — **"I need predicted binding poses for the top"** — truncated mid-phrase, no object.
3. `rev_linear_10`-type verbose essay — *"We're investigating host genetic susceptibility … deposited as SRA bioproject PRJNA456789 … identify coding variants that differ between the severity groups and separately determine which genes are differentially expressed … then give me an integrated shortlist … Please skip any initial read quality summaries; I've already verified that the data passed our institutional QC gates."* — over-complete essay (5× overspec) with an injected negation; reads as a grant methods paragraph, not a chat ask.

### Three example queries to KEEP

1. *"Perform quality assessment on my eight paired-end FASTQ files from Bacillus subtilis soil isolates and generate a draft genome assembly with minimum contig length 500 bp."* — concrete, one real parameter, realistic length and register.
2. *"I've got a shortlist of twelve lead compounds from our HTS campaign and need ADMET profiles on all of them to triage before moving into in vivo PK studies—can you generate the full property table?"* — credible industry triage ask; matches the user's real peptide example in voice.
3. *"I have twelve paired-end FASTQ files from ChIP-seq of H3K27ac in human CD4+ T cells (stimulated vs. resting). I need the enriched regions identified genome-wide and then ranked by signal strength so I can prioritize the top candidate enhancers for validation."* — exactly how a real ChIP user frames an identify-then-rank request; genuine fan-out-to-selection.

---

## 7. One-paragraph bottom line

The reverse-decomposition **design** (real accept-sets, need-satisfaction grading, real held-out
test, proven combo-disjoint split) is sound and worth keeping. The **generated TRAIN queries are not
yet representative of daily practical workbench use**: they are 4× too long, measurably over-complete
(3.5× the gold on average), written in one unmistakable generator voice, stripped of the tool-naming
style 12% of real users actually use, missing the real exotic domain tail, and — the blocking defect —
**16% are truncated stubs the round-trip validator wrongly passed as "ok".** Worse for the stated
purpose, the keep-filter selects *against* the under-specification that decomposition exists to test.
Fix the truncation validator first (it is a correctness bug, not a tuning knob), then re-weight to the
real distribution, invert the under-specification filter, relax the tool-name ban to a quota, and go
multi-generator with real-seed paraphrase harvesting from the enriched dev/S3 DB.
