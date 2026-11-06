# Bioconductor context-based method-selection benchmark

Tests whether a system picks the **correct Bioconductor method among confusable siblings** from rich
scientific context — the fine-grained analogue of RealBio's coarse `cross_domain_routing`. This is the gap
the existing Bioconductor work left open (Paper 2 measured *generation/citation* quality single-LLM;
RealBio routes to coarse nf-core pipeline names). See the design-validity gate:
`docs/20261004_BIOC_METHOD_SELECTION_DESIGN_GATE.md`.

## Data (`data.jsonl`, 24 items, 5 PASS groups)
Each item: `{id, query, candidates[], correct_method, acceptable_alts[], invalid_picks[], discriminator}`.
The query gives the **observable discriminator** (data shape / assay / input artifact) but never names a
method — it tests context interpretation, not keyword matching. All 19 candidate names are real entries in
the `workflows` table (verified). Groups:
- **og** ORA vs GSEA (discrete gene list → ORA; genome-wide ranked statistic → GSEA; GO/KEGG vs Reactome vs GMT)
- **as** microarray vs RNA-seq DE (two-color intensity → limma; integer counts → deseq2/edger; +report → nf-core/differentialabundance)
- **st** input-stage DE (count matrix vs Salmon quant vs multi-method report)
- **pr** proteomics labeling (TMT / LiP / PTM / label-free DDA)
- **sc** single-cell object-format (SingleCellExperiment → scran; h5ad → scdownstream; Seurat → seurat tools)

`DESeq2 vs edgeR` head-to-head is deliberately EXCLUDED (no observable discriminator — see the gate).

## Metric (`score.py data.jsonl predictions.jsonl`)
- **top1_accuracy** — pred ∈ {correct_method} ∪ acceptable_alts
- **invalid_regime_failure_rate** — pred ∈ invalid_picks (a *correctness* failure, e.g. ORA on ranked data,
  limma on counts, a TMT method on label-free data) — the metric that makes wrong-regime picks cost more
  than merely-suboptimal ones
- **wrong_but_real_rate** / **hallucination_rate** (pred not among candidates / not a real workflow)

## Conditions matrix (to run — reuses RealBio conventions, do NOT rebuild them)
`{bare LLM, LLM + KB-retrieval (BioMate harness), full harness}` × `{Claude, GPT, Gemini, an open-weight}`.
Predictions written per condition/model as `{id, prediction}` JSONL; score each with `score.py`. Expected
headline: bare LLMs discriminate close Bioc siblings poorly / hallucinate wrong-package methods; +KB closes
most of it; the gain is model-invariant → "the KB, not the model, picks the right method from context."
Ground context realism via the external DBs (`data_sources.py`/`federated_query.py`: KEGG/Reactome/GO/NCBI).
