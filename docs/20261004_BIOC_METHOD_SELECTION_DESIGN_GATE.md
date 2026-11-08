# Bioconductor context-based method-selection — design-validity gate

**Date:** 2026-10-04
**Purpose:** before building a Bioconductor *method-selection* benchmark, verify (per the hard lesson of the
multi-omics NO-GO, `docs/20260811_MULTIOMICS_SELECTION_BATTERY_DESIGN.md`) that each candidate sibling group
satisfies BOTH validity conditions:
  (i) the correct method **varies with scientific context**, and
  (ii) the correct method is **predictable from observable context features** (stated in the KB).
Pairs failing either condition are dropped — a benchmark where the answer isn't predictable is not a real
capability test.

Source of truth: `workflows` table of `backend/database/galaxy_ai_tools.db` (fields `description`/
`annotation`, `input_types`, `output_types`, `source`), queried 2026-10-04.

## PASS — qualifying groups (build on these)
| Group | Correct-choice discriminator (observable) | KB evidence | Strength |
|---|---|---|---|
| **ORA vs GSEA** `clusterprofiler` / `clusterprofiler_gene_set_enrichment_analysis` (+ `reactomepa`/`reactomepa_reactome_gsea`, `fgsea_over_representation_analysis`/`fgsea`) | discrete/unranked gene list (ORA) vs ranked statistic vector (GSEA) | descriptions literally say "DISCRETE gene list (DE genes at FDR<threshold)" vs "RANKED list ... running-sum test"; `input_types` = `gene_list.txt` vs `ranked_gene_list.txt` | **Strong** (flagship; same pathway DB, only input form differs — controlled) |
| **Microarray vs RNA-seq DE** `limma` vs `deseq2`/`edger` | two-color microarray intensity (.gpr/targets) vs un-normalized integer counts | `limma` in=`targets.txt`,`.gpr`; `deseq2` in=`cts (un-normalized integer counts)`; `edger` in=`TableOfCounts` | **Strong** (assay-type discriminator) |
| **Input-stage DE** `deseq2` vs `deseq2_de_from_transcript_abundance` vs `nf-core/differentialabundance` | raw count matrix (single method) vs Salmon `quant.sf` (transcript) vs count-matrix + multi-method report | `input_types` differ: `cts` vs `quant.sf.gz` vs `counts_matrix,samplesheet`; nf-core desc "does NOT process raw FASTQ" | **Strong** (input-artifact discriminator) |
| **Proteomics labeling** `msstatstmt` / `msstatslip` / `MSstatsPTM` / `nf-core/proteomicslfq` | TMT vs LiP-MS vs PTM vs label-free DDA | descriptions state TMT / LiP-MS+TrP / PTM(DDA,DIA,SRM,TMT) / "DDA LFQ (OpenMS)" | **Strong** (labeling/experiment-type discriminator) |
| **Single-cell object-format (PARTIAL)** `scran` (SingleCellExperiment) vs Seurat-ecosystem tools (`ucell_seurat_workflow`…) vs `nf-core/scdownstream` (h5ad/count-matrix pipeline) | input object format + single-step vs pipeline | `input_types`: `sce.ready` vs `seurat.object` vs `h5ad,counts_matrix` | **Partial** (object-format predictable; keep those, DROP "which clustering algorithm") |

## DROP — fails predictability (the honest NO-GO)
| Group | Why dropped |
|---|---|
| **DESeq2 vs edgeR** (head-to-head) | both take raw integer counts for standard designs; the choice is subtle statistical preference (NB-GLM+empirical-Bayes vs qCML/QL-F) with **no observable context feature** that makes one uniquely correct. Including it would reward an arbitrary label. (Edge cases — very small n favouring edgeR exact test, specific complex designs — are too subtle to label reliably.) |
| Generic "which single-cell clustering algorithm" | multiple valid choices for the same input; not uniquely predictable. |

## Benchmark design (on the PASS groups only)
- **Dataset** `evaluation/datasets/bioc_method_selection/`: each item = rich scientific context →
  one correct method among confusable siblings, drawn ONLY from PASS groups. Context specifies the
  observable discriminator (e.g. "312 genes significant at FDR<0.05" → ORA; "all 18k genes ranked by
  signed −log10 p" → GSEA), with real organisms/pathways/accessions pulled from the external DBs
  (`data_sources.py`/`federated_query.py`: KEGG/Reactome/GO/NCBI/ClinVar) so it tests context
  interpretation, not keyword matching.
- **Conditions matrix** (reuse RealBio's single scorer + bare/catalog prediction-file convention — do NOT
  rebuild): `{bare LLM, LLM+KB-retrieval, full harness}` × `{Claude, GPT, Gemini, an open-weight}`.
- **Metric:** top-1 method accuracy + **invalid-regime failure rate** (ORA-on-ranked-data, limma-on-counts,
  TMT-method-on-LFQ-data = correctness failures, not low scores) + error split (hallucinated method vs
  wrong-but-real method), reusing RealBio's hallucinated-selection vs discrimination-error taxonomy.
- **Expected headline:** bare LLMs discriminate close Bioc siblings poorly / hallucinate wrong-package
  methods; +KB closes most of it; the gain is model-invariant → "the KB, not the model, picks the right
  Bioconductor method from scientific context" — the fine-grained analogue of the routing catalog dividend.

## Status
- [x] Design-validity gate run on the real KB fields → 5 PASS groups (ORA/GSEA flagship), 2 DROP.
- [ ] Build the `bioc_method_selection` dataset on the PASS groups (grounded in KB + external DBs).
- [ ] Run the multi-LLM × bare/KB/harness matrix; score top-1 + invalid-regime; report the KB dividend.
