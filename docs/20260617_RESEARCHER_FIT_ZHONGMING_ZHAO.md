# Researcher Fit — Dr. Zhongming Zhao (UTHealth Houston)

**Date:** 2026-06-17
**Scholar:** https://scholar.google.com/citations?user=eDRMnHQAAAAJ
**Lab GitHub:** https://github.com/bsml320 (Bioinformatics and Systems Medicine Lab)
**Lab page:** https://www.uth.edu/bioinfo/
**Citation metrics:** h-index 90, i10 435, 35.6k citations, 492 articles
**Research areas:** Bioinformatics, precision medicine, deep learning, single-cell, viral integration, cancer immuno-oncology

## Last 3 years — publication clusters

| Cluster | Recent papers | Common method |
|---|---|---|
| **Single-cell + immune-oncology** | Turep (bioRxiv 2026) cross-cancer tumor-reactive T cells, fibroblast heterogeneity (iScience 2025), intratumor immune diversity (npj Precision Oncology 2025), scGWAS, Scupa, DeepTR | Atlas-scale scRNA-seq + spatial transcriptomics for immunology |
| **Multi-omics QTL + Alzheimer's** | PRISM-xQTL (Alz & Dem 2026), MethConvTransformer cross-tissue AD (arXiv 2026), BrainGeneBot (Alz & Dem 2025), GENEVIC, snMultiome sEOAD | Genome × transcriptome × methylome integration with GPT-assisted exploration |
| **Viral integration + cancer genomics** | VISDB 2.0 (Sci Data 2026), HSV-1 oncolytic + IGF1R resistance, copper-homeostasis miRNA + oHSV in glioblastoma | Curated databases + viral integration site mapping |
| **Deep-learning predictive frameworks** | NetRNApan (Brief Bioinform 2025), ConvNeXt brain tumor MRI (Bioengineering 2026), ImmuneApp, NetBCE, DeepFun, VAEN, fadvi | Sequence/image → biological property prediction |
| **Translational** | C3ar1 microglia/macrophage (Mol Psychiatry 2025), HGSOC prognostic GRN, *Candida albicans* virulence | Disease-mechanism studies powered by their tooling |

## Code availability — verified 2026-06-17

| Tool | Repo | License | Last update | Stars |
|---|---|---|---|---|
| **turep** (cross-cancer tumor-reactive T cells) | `bsml320/turep` | **MIT** | 2026-04-21 | - |
| **NetBCE** (B-cell epitope prediction) | `bsml320/NetBCE` | **MIT** | 2026-02-04 | 7 |
| **ImmuneApp** (HLA-I epitope) | `bsml320/ImmuneApp` | **MIT** | 2025-09-12 | 14 |
| **CytoRescue** | `bsml320/CytoRescue` | **MIT** | 2026-01-22 | - |
| **fadvi** (single-cell factor disentanglement) | `bsml320/fadvi` | **MIT** | 2025-11-05 | - |
| **scGWAS** | `bsml320/scGWAS` | **GPL-3.0** | 2026-05-18 | 28 |
| **NetRNApan** | `bsml320/NetRNApan` | no LICENSE | 2026-05-25 | 2 |
| **Scupa** (immune cell polarization) | `bsml320/Scupa` | NOASSERTION | 2026-05-25 | 9 |
| **BrainGeneBot** | `bsml320/BrainGeneBot` | no LICENSE | 2026-06-17 | 2 |
| **GENEVIC** | `bsml320/GENEVIC` | no LICENSE | 2026-01-16 | 2 |
| **CancerGen-RAG** | `bsml320/CancerGen-RAG` | NOASSERTION | 2026-01-21 | - |
| **VAEN** (drug response imputation) | `bsml320/VAEN` | no LICENSE | 2026-01-12 | 21 |
| **DeepTR**, DeepFun, DeepHTLV, deCS, deTS, BrainSpan, MSEA, vTRs, JAD | `bsml320/*` | mostly no LICENSE | 2024–2025 | mixed |
| **VISDB 2.0** | hosted at lab page; no GitHub repo found | web DB | — | — |
| **PRISM-xQTL**, **MethConvTransformer**, **BDCD** | **not found** on bsml320 | — | — | — |

## BioMate fit assessment

### Tier-A — drop-in workflows this week (license-clean, mature, demo-ready)

1. **turep + Scupa + ImmuneApp** — three single-cell immuno-oncology tools that compose into a coherent chain: predict CD8+ tumor-reactive T cells (turep) → annotate polarization state (Scupa) → predict HLA-I epitope binding for top neoantigens (ImmuneApp). Chain narrative writes itself; matches BioMate's existing scRNA-seq routing.
2. **scGWAS** — GPL-3.0, 28★, single-cell GWAS that bridges Zhao's genetics work to single-cell. Slots alongside Bioconductor scRNA-seq chains; pairs with Dr. Zhi's TorchGWAS for a complete GWAS surface.
3. **NetBCE + VAEN + fadvi** — three small, sharp deep-learning models for B-cell epitopes, drug-response imputation, and single-cell disentanglement. Each is a 1-step workflow runnable via `run_code`.

**Effort:** ~3–4 days per chain (vs ~2 days per single workflow for Zhi's), because turep/Scupa/ImmuneApp compose into a multi-phase chain with non-trivial data flow.

### Tier-B — needs a license conversation (current code, NOASSERTION or no LICENSE)

NetRNApan, Scupa (NOASSERTION — needs clarification), BrainGeneBot, GENEVIC, CancerGen-RAG, VAEN, DeepTR, DeepFun, DeepHTLV, MSEA, BrainSpan. All published-with-paper but missing permissive license. Same one-line ask as Zhi's lab.

### Tier-C — referenced in papers, not on GitHub

**VISDB 2.0** (web-hosted database — could be wrapped as a BioMate reference dataset rather than a workflow), **PRISM-xQTL** (Alz & Dem 2026 — code expected post-publication), **MethConvTransformer** (arXiv 2026 — preprint stage), **BDCD** (Database 2026). Worth asking which are ready to release.

### Special opportunities unique to Zhao's profile

- **CancerGen-RAG** — a RAG over cancer-genetics literature. BioMate already runs a chat agent over indexed workflows; integrating their RAG corpus as a retrieval source would let queries like *"what's the evidence for BCMA in MM?"* return papers + a runnable workflow in one shot. Strong differentiator vs BioGPT/PubMed-only chat.
- **BrainGeneBot** — GPT-engineered Alzheimer's polygenic-risk explorer. BioMate's chat router can host this as a domain agent, contributing to the AD-themed demo set alongside Zhi's UDIP imaging-genetics work.
- **VISDB 2.0** as a curated dataset — register as a BioMate "reference resource" (parallel to UCSC, gnomAD), so any HSV/HPV/HBV viral-integration query can pull from it.

## Cross-researcher synergy (Zhi + Zhao, same campus)

| Shared theme | Zhi tool | Zhao tool | Joint BioMate chain |
|---|---|---|---|
| **GWAS** | TorchGWAS, RaPID, HiFiMAP | scGWAS | one chain: bulk GWAS → IBD partitioning → single-cell GWAS overlay |
| **Alzheimer's** | UDIP brain phenotypes | BrainGeneBot, PRISM-xQTL, MethConvTransformer | imaging phenotype → xQTL → polygenic risk |
| **Clinical EHR** | Med-BERT, vancomycin RL | CancerGen-RAG | foundation-model EHR backbone + RAG corpus |
| **Drug discovery** | FDA (protein-ligand) | turep / ImmuneApp (neoantigen) | small-molecule + immunotherapy parallel rails |

Pitching both labs together (UTHealth Houston, same school) is more efficient than two separate engagements.

## Concrete pitch (one paragraph)

> Dr. Zhao — your lab publishes high-impact tools across single-cell, viral integration, multiomics QTL, and clinical RAG, but every tool ships as a standalone GitHub repo that users assemble themselves. BioMate is the execution + reporting harness: chain your turep + Scupa + ImmuneApp into a single chat-routable tumor-reactive T-cell pipeline, run it on AWS Batch, and produce a 7-tab report (Findings, Outputs, Methods, Parameters, Software, Citations, QC audit) that cites your papers via the (why?) anchor. We'd start by integrating the four MIT-licensed tools at no cost; the Alzheimer's stack (BrainGeneBot, PRISM-xQTL, MethConvTransformer) becomes a paid second phase once you release them. Given the campus overlap with Dr. Zhi's group, a joint UTHealth pilot may compound the value for both labs.

## Open items before reaching out

- [ ] Confirm VISDB 2.0 — wrap as dataset or proxy as a query API
- [ ] Confirm release status of PRISM-xQTL, MethConvTransformer, BDCD
- [ ] Pre-build the turep+Scupa+ImmuneApp chain as a demo
- [ ] Decide whether to pitch Zhi + Zhao jointly or sequentially
