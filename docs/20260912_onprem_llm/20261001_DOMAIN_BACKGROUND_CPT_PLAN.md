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

## Build order (cheapest, highest-leverage first; no GPU until corpus is reviewed)
1. GTN (CC-BY) — clone, extract tutorial concept markdown → `background_corpus.jsonl` [START HERE]
2. Bioconductor + nf-core conceptual docs
3. PMC OA review subset (query for review-type OA)
4. OpenStax + Wikipedia core concepts + open stats text
5. Rebalance mix + CPT run (spot GPU) + eval

## Guardrails (lessons from this session)
- Do NOT put facts in the corpus (the closed-book-SFT / SMILES-recall mistake, twice). Concepts only.
- Verify licences before ingest; keep a provenance manifest per source.
- Eval must be leakage-split from the corpus (the systemic-leakage audit lesson).
- CPT helps ONLY the judgment/knowledge tasks — don't expect it to move routing/retrieval (invariant).
