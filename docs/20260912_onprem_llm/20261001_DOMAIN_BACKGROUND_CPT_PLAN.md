# Domain Background Knowledge for the On-Prem LLM — Plan

**Date:** 2026-10-01
**Goal (user):** "I want the LLM to grasp more domain background knowledge."
**Reconciliation with "facts → retrieval":** background knowledge ≠ facts. Facts (SMILES, gene lists,
param values, accessions, specific study findings) stay in retrieval. **Background knowledge** = the
stable conceptual scaffold (mechanisms, methodology, statistics, experimental design, the "why") that
lets the model *reason over* retrieved facts. That scaffold is stable + finite → it belongs in weights
(CPT), and it is exactly what powers the 4 irreducible-judgment tasks + knowledge QA.
Companion: [[20261001_TASK_FLOWS_DB_SUPPORT]], [[20261001_LLM_HARNESS_TASK_SPLIT]].

## Diagnosis — why the current corpus doesn't impart background (mid500 ≈ base)
Current mid-train mix (`midtrain_domain_v1strong.composition.json`):
- **literature 73.2%** — PubMed *abstracts* (frontier findings, not foundational concepts)
- **structured 15.7% (repeated 6×)** + **KG ~8%** + **db_catalog** — **raw FACTS** baked into weights
- pmc_fulltext/tooldoc 3.1%
So the corpus is **frontier-findings + facts**, with **no foundational background layer** (no
textbook/review/methodology). CPT on facts is a no-op on retrieval-grounded tasks (mid500 confirmed)
and never builds the reasoning scaffold. This is the gap.

## Definition — what the background corpus IS and ISN'T
**INCLUDE (stable concepts / reasoning scaffold):**
- Molecular & cell biology mechanisms (transcription, translation, regulation, signalling)
- Omics methodology concepts: what RNA-seq/scRNA/ATAC/WGS/proteomics/metabolomics/cryo-EM measure;
  library prep, strandedness, UMIs, batch effects — *conceptually*
- Bioinformatics algorithms *conceptually*: alignment, assembly, quantification, variant calling, QC
- Statistics: hypothesis testing, multiple testing / FDR, effect size, normalization, the DE model
  families (why DESeq2 vs edgeR vs limma), power, confounding
- Experimental design principles; interpretation principles (what a result *means*)
- Pharmacology/ADMET concepts: absorption/distribution/metabolism/excretion/tox, PK/PD, hERG, DILI

**EXCLUDE (facts → retrieval, never weights):**
- Specific gene/protein/pathway lists, SMILES, accession numbers, param values, allowed_values
- Specific study findings / numeric results (PubMed abstracts' core content)
- Catalog/DB/KG rows (the current structured/kg/db_catalog)

## Sources (license-clean, conceptual)
| Source | Licence | Why |
|--------|---------|-----|
| **Galaxy Training Network** (github galaxyproject/training-material) | CC-BY | conceptual bioinformatics tutorials — BioMate IS Galaxy-based; highest fit |
| **Bioconductor vignettes** (intro/concept sections) | Artistic-2.0/CC | the workflows ARE Bioconductor; explain the *why* |
| **nf-core pipeline docs** (concept/usage rationale) | MIT | the nf-core pipelines' conceptual docs |
| **PMC Open-Access *review* subset** (filter: review + OA) | CC-BY/OA | reviews = background synthesis (unlike primary abstracts) |
| **OpenStax Biology / Microbiology** | CC-BY | foundational molecular/cell biology |
| **Wikipedia** core concept articles (bio/stats/methods) | CC-BY-SA | broad concept coverage |
| **Open stats / experimental-design texts** | CC | the statistics scaffold |

## Recipe
1. **Build the background corpus** (no GPU): fetch + clean the sources above into
   `background_corpus.jsonl` (concept documents, dedup, strip fact-tables/reference-lists). Target a
   few hundred M tokens of *concepts*.
2. **Rebalance the CPT mix:** down-weight facts (drop/÷ structured-repeat, drop KG/db_catalog from CPT
   — they're retrieval, not weights), replace primary-abstract literature with the **review** subset,
   add `background_corpus` as the dominant domain layer. Keep FineWeb-Edu general replay (25–75) to
   avoid forgetting.
3. **CPT → SFT (open-book) → reasoning** (the Insilico 3-stage; CPT is where background lands).
4. **Eval:** `knowledge_recall` + `scientific_qa` (MCQA — a VALID grader) as the background-grasp
   metric, plus the judgment tasks (findings_interpretation, model_selection) qualitatively. Include
   the **null**: does background CPT beat the fact-heavy mid500 (0.26) and lift knowledge MCQA above
   the current SFT (0.66/0.48)? Leakage-split the eval from the corpus by source/family.

## Recipe precedent — what established life-science LLMs train on (verified 2026-10-01)
- **MEDITRON** (Llama-2): CPT on **GAP-Replay 48.1B tok** = clinical guidelines (46K) + 16.1M PubMed/PMC
  abstracts + full-text (5M papers) + general replay. (Our spot_train.sh already mimics "Meditron-style".)
- **PMC-LLaMA:** MedC-K = 4.8M papers + **30K TEXTBOOKS** (knowledge injection) → instruction tune.
  **Textbooks are core to the recipe — our missing layer.**
- **TxGemma / Tx-LLM** (drug): fine-tuned on **TDC** (66 therapeutic tasks, 7M examples) — this is drug
  *task/benchmark* data (maps to our ADMET/PBPK/BOIN benchmarks), NOT background.
- Pattern: **CPT on papers + guidelines + textbooks + replay → SFT.** We have papers
  (`pmc_fulltext_bulk`) + DB-concepts; add **textbooks + guidelines**.
- Sources: MEDITRON arXiv 2311.16079; PMC-LLaMA (PMC11639126); TxGemma (goo.gle/TxGemma).

## Textbook + drug-knowledge layer (license-clean for commercial use)
PMC-LLaMA's 30K textbooks were library-sourced (licence murky). Use CC-licensed only:
| Source | Licence | Drug depth? |
|--------|---------|-------------|
| OpenStax (Biology 2e, Microbiology, **Chemistry 2e**) | CC-BY | chem foundation |
| LibreTexts (Biology, Biochemistry, **Pharmacology**, **Medicinal Chemistry**, Organic) | CC (filter NC) | **yes — primary drug background** |
| Wikibooks (Pharmacology, Cell Biology, Biochemistry) | CC-BY-SA | yes |
| StatPearls (NCBI Bookshelf) | CC-BY | clinical pharmacology |
| PMC OA **review** subset (ADMET / PK-PD / drug-discovery reviews) | CC-BY/OA | yes |
| DB drug_discovery (61 wf) + pharmacology tool `scientific_context` | internal | BioMate-specific (already in corpus) |
Facts (DrugBank/ChEMBL rows, SMILES) stay in retrieval.

## Concrete mix recipe (concept-dominant, facts out) — via build_midtrain_mix.py
- `--struct background_corpus.jsonl --struct-repeat 3` → up-weight our clean DB+GTN concept seed (2.5M tok)
- `--lit <pmc_fulltext_FILTERED>.jsonl --lit-keep-every K --dedup --min-chars 400` → concept VOLUME
- **omit `--kg`**, pass **no** db_catalog/ontology/structured-fact extras → facts stay in retrieval
- replay (FineWeb-Edu 25/75) stays at train time (anti-forgetting)

## Model-size comparison: 9B + 27B (user, 2026-10-01)
Background grasp scales with capacity (unlike harness-carried tasks, which are size-invariant — routing
0.94 even on 4B). So compare **med=Qwen3.5-9B** (Insilico's winner, beat Gemini-3.1-Pro) vs
**large=Qwen3.8-27B** (capacity ceiling) — both configured in spot_train.sh.
- **Sequence 9B first** (tractable, cheaper; proves background-CPT beats the fact-heavy mid500), then 27B.
- Infra: 27B needs 48GB GPUs (g6e L40S / A100) + QLoRA + gradient-checkpointing; spot (g6.2xlarge was
  heavily reclaimed 2026-10-01 — prefer g5/g6e, relaunch-on-reclaim wrappers).

## Volume reality
Our concept corpus (~2.5M tok, DB-primary) is a **quality seed, not CPT volume**. CPT needs hundreds of
M–B tokens (Meditron 48B, PMC-LLaMA 4.8M papers). Volume must come from **`pmc_fulltext_bulk` (8.8GB)**,
but it contains digitized junk (e.g. 1867 editorials) → needs a **modern-biomedical filter** (year ≥ ~2000,
biomedical MeSH/journal, prefer review/full-text) before use. That filter is the critical remaining data step.

## Build order (cheapest, highest-leverage first; no GPU until corpus + volume are ready)
1. ✅ GTN concepts + ✅ **DB enrichment (primary)** → `background_corpus.jsonl` (2.5M tok)
2. **PMC filter**: modern-biomedical filter over `pmc_fulltext_bulk` → concept VOLUME [critical next]
3. Optional textbooks: OpenStax (CC-BY) + LibreTexts pharmacology (licence-gated) for drug depth
4. Rebalance mix (recipe above) + review composition
5. CPT **9B** (spot) → SFT → eval (knowledge MCQA + judgment vs mid500); then CPT **27B**

## Guardrails (lessons from this session)
- Do NOT put facts in the corpus (the closed-book-SFT / SMILES-recall mistake, twice). Concepts only.
- Verify licences before ingest; keep a provenance manifest per source.
- Eval must be leakage-split from the corpus (the systemic-leakage audit lesson).
- CPT helps ONLY the judgment/knowledge tasks — don't expect it to move routing/retrieval (invariant).
