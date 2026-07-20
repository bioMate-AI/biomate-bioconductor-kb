# Key Literature — Briefs, Detailed Reading, and Datasets/Benchmarks

**Date:** 2026-07-12
**Purpose:** Manuscript-citable briefs for four key papers (scFM review, CANVAS, agentic-AI perspective, AI-agents survey), plus a longer detailed reading that extracts every benchmark evaluation, dataset, and public dataset named in each. Citations + BibTeX at the end.

> Verification note: CANVAS and the Nat Biotech perspective are behind publisher paywalls; their bibliographic detail is assembled from PubMed + abstract + press coverage and should be confirmed against the publisher page before submission. The scFM review and the BiB survey are open-access (PMC) and were read in full.

---

## 1. Single-cell foundation models (review)

### Short brief
Baek, Song & Lee review **single-cell foundation models (scFMs)** — transformer models pretrained on massive single-cell corpora that treat cells as "sentences" and genes as "words." They survey ~12 models and their downstream tasks (cell-type annotation, batch correction, imputation, gene-network inference). Key caveat: **fine-tuning yields substantial gains, but zero-shot scFMs often underperform specialized tools**, and the field lacks unified benchmarks, handles rare cell types poorly, and remains hard to interpret.

### Detailed reading
The paper's central framing is that scFMs import the NLP foundation-model paradigm (self-supervised pretraining → fine-tune to many tasks) into single-cell biology. Architecturally, most are transformers that tokenize a cell's expression profile; they extract latent structure at both the cell and gene level for heterogeneity and regulatory-network analysis. The authors are explicit that scaling helps but does not settle the field: zero-shot performance frequently trails task-specific tools, and the lack of a common benchmark makes cross-model claims unreliable — which is exactly the caution to cite when arguing that an orchestration/verification layer (not a bigger model) is where value accrues.

### Benchmarks, datasets, public datasets named
**Pretraining corpora (model → scale → source):**
| Model | Cells | Source(s) |
|---|---|---|
| scBERT (2022) | 1.1M | PanglaoDB (209 human datasets, 74 tissues) |
| Geneformer (2023) | 30M | Human Cell Atlas, EMBL-EBI Single Cell Expression Atlas, PanglaoDB, Tumor-Immune Single-Cell Hub, GEO, SRA |
| tGPT (2023) | 22.3M | HCA, Single Cell Expression Atlas, COVID-19 Atlas, Tabula Muris, Mouse Cell Atlas |
| CellLM (2023) | 2M | PanglaoDB, CancerSCEM |
| CellPLM (2023) | 11M | Human Tumor Cell Atlas, HCA, GEO, CosMx |
| scGPT (2024) | 33M | CELLxGENE, HCA, PanglaoDB |
| scFoundation (2024) | 50M | GEO, HCA, EMBL-EBI, hECA, DISCO |
| Geneformer2 (2024) | 103M | Geneformer1 + Broad Single Cell Portal, CELLxGENE, Brotman Baty–Allen atlases |
| UCE (2024) | 36M | CELLxGENE (8 species) |
| GeneCompass (2024) | 126M | GEO, ArrayExpress, CNCB, CELLxGENE |
| Nicheformer (2024) | 110M | GEO, CosMx, Xenium, MERFISH (human + mouse) |
| SCimilarity (2024) | 23.4M | GEO, CELLxGENE, manual curation |
| scPRINT (2025) | 54M | CELLxGENE (human + mouse) |

**Major repositories referenced:** CZ CELLxGENE (>100M cells), Human Cell Atlas, NCBI GEO/SRA, EMBL-EBI Expression Atlas, PanglaoDB, Human Ensemble Cell Atlas (hECA).
**Benchmark suite named:** **scEval** — evaluates scFMs across eight canonical single-cell tasks under consistent conditions. The review stresses that unified benchmarking remains the exception; most models ship their own task set.

---

## 2. CANVAS — virtual spatial tumor profiling from H&E (Cell)

### Short brief
Li et al. present **CANVAS** (Cellular Architecture and Neighborhood-informed Virtual AI-driven Spatial profiling), which infers tumor-microenvironment organization directly from routine **H&E histopathology**. Built on an atlas of **>18M cells profiled by 41-plex spatial proteomics across 457 NSCLC patients**, it defines **10 reproducible cellular neighborhoods** and was validated in **>5,000 patients across 9 cancer types**, supporting prognostic modeling, spatial-ecotype stratification, and immunotherapy-outcome prediction.

### Detailed reading
CANVAS is the exemplar of a **vertical, single-modality** virtual-cell platform: it learns a mapping from cheap, ubiquitous H&E images to expensive spatial-proteomic structure, then generalizes that mapping across cancer types. Its scientific contribution is the reproducible 10-neighborhood decomposition of the TME and the demonstration that spatial ecotypes carry prognostic and immunotherapy-response signal at population scale. For BioMate's positioning, CANVAS is the clean contrast case: a powerful point solution that an orchestration layer would *call as a tool*, not compete with — it does one modality superbly and does not chain across omics.

### Benchmarks, datasets, public datasets named
- **Discovery cohort:** proprietary atlas — >18M cells, 41-plex spatial proteomics, 457 NSCLC patients.
- **Validation:** >5,000 patients spanning 9 cancer types (cohort identities to confirm from full text; likely includes TCGA-based H&E cohorts — verify).
- No open benchmark suite; evaluation is prognostic/response-association against clinical outcomes. (Confirm any public data-release statement in the full text.)

---

## 3. Agentic AI and in silico team science (Nature Biotechnology)

### Short brief
Li, Saini, Hernandez & Moore argue that **agentic AI systems act as "teams of intelligent computational experts"** capable of rivaling human performance on labor-intensive research tasks, coining **"in silico team science"** for human–AI collaborative research. They map three application areas — **drug discovery, data analysis, biomarker identification** — spanning literature review, hypothesis generation, and interpretation, and flag deployment barriers (accountability, data provenance, veracity).

### Detailed reading
This is a perspective/review, not a benchmark paper. Its value as a citation is conceptual: it names and legitimizes the exact thesis of a cross-specialty orchestration platform — autonomous agents that plan, use tools, take specialist feedback, and collaborate with humans as a "team." It distinguishes agentic systems from narrow single-function models by their autonomy and contextual decision-making, and it raises the governance agenda (accountability frameworks, provenance, veracity of AI recommendations) that any production scientific-agent system must answer. Cite it to frame multi-agent scientific orchestration and to motivate provenance/verification features.

### Benchmarks, datasets, public datasets named
None of substance — it is a forward-looking perspective. It references application *areas* and deployment considerations rather than specific datasets or benchmark suites. (Use §4 below for the benchmark/dataset landscape.)

---

## 4. AI agents for biological research (survey, Briefings in Bioinformatics)

### Short brief
Qi et al. synthesize **>100 studies (Jan 2023–Sep 2025)** on AI agents in biology, distinguishing agents from static foundation models by **iterative, goal-directed reasoning with autonomous planning and feedback**. They organize the field along five axes — tasks, architectures, interaction modes, evaluation strategies, resource integration — across clinical analytics, molecular/drug design, multi-omics, and literature discovery, and identify six open challenges (autonomy beyond chatbots, hallucination control/factual grounding, domain-knowledge embedding, privacy, standardized evaluation, scalability).

### Detailed reading
The most useful single map of the agent landscape for our purposes. Its taxonomy (single-agent vs multi-agent vs neuro-symbolic; step-by-step vs zero-shot vs hybrid human-AI; knowledge- vs tool-augmented) is a ready-made framework for positioning BioMate. Critically, the survey's headline gap — **"standardized evaluation remains absent; most systems use qualitative case studies rather than formal benchmarks"** — is a direct opening: a platform that reports gold-standard, benchmarked results (see companion showcase doc) differentiates on exactly the axis the field is weakest. Its recommendations (lightweight domain-specialized models, multi-agent robustness, transparent modular systems as infrastructure) align with our tiered-routing + verification + curated-atlas plan.

### Benchmarks, datasets, public datasets named
**Public datasets / knowledge bases the reviewed agents use:**
- *Genomics & clinical:* HPO (Human Phenotype Ontology), NCBI API, ClinVar, CPIC, PharmGKB, Orphanet, GeneReviews, MAxO/MONDO ontologies, PubTator
- *Single-cell/transcriptomics tooling:* CellChat, SCENIC, LIGER, scVelo
- *Literature/KG:* PubMed, bioRxiv, arXiv
- *Multi-omics:* pQTL data, GWAS datasets, a precancerous multi-omics resource

**Named agent systems reviewed (partial):** Biomni, GeneGPT, CellAgent, GeneAgent, CRISPR-GPT, AutoMAxO, Co-Scientist, BRAD, AutoBA, SteLLA, PhenoGPT, ChIP-GPT, CancerGPT, AutoPM3, VarChat, GP-GPT, RNA-GPT, and ~15 more.
**Benchmark/eval frameworks referenced:** DREAM Challenge (omics benchmarks), AlphaFold structures (pathogenicity calibration), GeneTuring (QA benchmark). The survey's own finding: formal benchmarking is the exception.

---

## Citations (Vancouver)

1. Baek S, Song K, Lee I. Single-cell foundation models: bringing artificial intelligence into cell biology. *Exp Mol Med*. 2025;57(10):2169–2181. doi:10.1038/s12276-025-01547-5
2. Li Y, Li Z, Quinton R, Ji Y, Zhang X, … Li R. Cellular architecture and neighborhood-informed virtual spatial tumor profiling from histopathology. *Cell*. 2026. doi:10.1016/j.cell.2026.05.031
3. Li B, Saini AK, Hernandez JG, Moore JH. Agentic AI and the rise of in silico team science in biomedical research. *Nat Biotechnol*. 2026;44(5):711–725. doi:10.1038/s41587-026-03035-1
4. Qi C, Wang W, Jiang S, Liu Q, Song X, Fang H, Wei Z. Artificial Intelligence agents for biological research: a survey. *Brief Bioinform*. 2026;27(1):bbag075. doi:10.1093/bib/bbag075

## BibTeX

```bibtex
@article{baek2025scfm,
  title   = {Single-cell foundation models: bringing artificial intelligence into cell biology},
  author  = {Baek, Suyeon and Song, Kwanghwan and Lee, Insuk},
  journal = {Experimental \& Molecular Medicine},
  volume  = {57}, number = {10}, pages = {2169--2181}, year = {2025},
  doi     = {10.1038/s12276-025-01547-5}
}
@article{li2026canvas,
  title   = {Cellular architecture and neighborhood-informed virtual spatial tumor profiling from histopathology},
  author  = {Li, Yuchen and Li, Zhe and Quinton, Ryan and Ji, Yuanfeng and Zhang, Xiaoming and Li, Ruijiang},
  journal = {Cell}, year = {2026}, doi = {10.1016/j.cell.2026.05.031}
}
@article{li2026agentic,
  title   = {Agentic AI and the rise of in silico team science in biomedical research},
  author  = {Li, Binglan and Saini, Anil Kumar and Hernandez, Jose Guadalupe and Moore, Jason H.},
  journal = {Nature Biotechnology},
  volume  = {44}, number = {5}, pages = {711--725}, year = {2026},
  doi     = {10.1038/s41587-026-03035-1}
}
@article{qi2026agents,
  title   = {Artificial Intelligence agents for biological research: a survey},
  author  = {Qi, Chen and Wang, Wei and Jiang, Shuo and Liu, Qi and Song, Xin and Fang, Hui and Wei, Zhi},
  journal = {Briefings in Bioinformatics},
  volume  = {27}, number = {1}, pages = {bbag075}, year = {2026},
  doi     = {10.1093/bib/bbag075}
}
```
