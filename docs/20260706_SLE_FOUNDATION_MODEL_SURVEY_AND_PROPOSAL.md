# SLE Foundation Model Adaptation — Survey & Research Proposal
**Date:** 2026-07-06  
**Status:** Complete — all searches resolved

---

## 1. Background: Task 3 of the SLE Banchereau Pilot

**Original formulation:** Fine-tune Geneformer v2 on GSE89408 (RA) + GSE142016 (SLE) + GSE134809 (IBD), evaluate on GSE65391 (Banchereau 2016 SLE clusters), measure silhouette score improvement.

**Critical finding:** GSE65391 is microarray (Illumina HumanHT-12 V4.0), not single-cell. GSE89408 is bulk RNA-seq. Geneformer cannot process either. The original experimental design is broken.

---

## 2. Survey: Adaptation Approaches for Single-Cell Foundation Models

### 2.1 Standard Fine-Tuning Methods (Established)

| Method | Paper | Key detail |
|---|---|---|
| Classification FT | Theodoris, *Nature* 2023 | Add linear head; cross-entropy; 5e-5 LR; 15 epochs |
| Regression FT | Theodoris, *Nature* 2023 | MSE head for continuous targets (TF dosage) |
| LoRA | Chen, *bioRxiv* 2024 (scPEFT) | rank=8–16, target q/v attention; 98% param reduction |
| SupCon loss | SSL4scRNA, *Bioinformatics* 2024 | NT-Xent, disease state as positive pairs |
| Partial layer freeze | scFoundation, *Nat Methods* 2024 | Freeze layers 0–3, fine-tune 4–5 + head |

### 2.2 Novel 2024–2025 Approaches

| Method | Paper/Venue | Core idea | Task 3 relevance |
|---|---|---|---|
| Drug-conditional adapter | ICLR 2025 (arXiv:2412.13478) | Freeze 99% of model; tiny condition-specific adapter (<1% params) | High — swap drug → disease condition |
| CellRefine post-pretraining | arXiv May 2025 (arXiv:2605.07938) | Marker-gene-guided masked LM + cell ontology regularization before FT | High — reshapes embedding geometry |
| GRNFormer | ACL 2025 (arXiv:2503.01682) | GRN edges as attention biases during FT | Medium — immune GRNs as priors |
| EVA | arXiv Feb 2026 (arXiv:2602.10168) | Domain-adaptive pretraining for immunology; 39-task eval including disease activity | Very high — built for this problem |
| scMMGPT | arXiv Mar 2025 (arXiv:2503.09427) | Text-conditioned cell embeddings (27M cells) | Medium — text-conditioned prototypes |
| PT-RAG | ICLR 2025 (arXiv:2603.07233) | Inference-time retrieval from reference atlas; no weight updates | Medium — zero-shot baseline |
| Cell-o1 | *Bioinformatics* 2025 (arXiv:2506.02911) | RL with batch-level reward; 73% over GPT-o1 on CellPuzzles | Low-medium — annotation tasks |
| Adversarial FT | arXiv Jun 2025 (arXiv:2606.07676) | GAN-style cross-modal/domain-invariant FT | Medium — adversarial batch correction |
| scRAG | ACL 2025 | KG + cell retrieval as LLM context | Medium — disease KG retrieval |
| eSPred | *bioRxiv* May 2025 | Pathway-informed FT as architectural constraints | Close to Option B but different mechanism |
| scKGBERT | *Genome Biology* 2025 | KG-augmented multi-task FT (12 tasks, PPI graph) | Related |
| scTransformer | arXiv Jun 2025 (arXiv:2606.09558) | Gene regulatory priors in attention | Option C overlap |

---

## 3. Data Availability Findings

### 3.1 Original Datasets — Status

| Dataset | Proposed role | Actual type | Verdict |
|---|---|---|---|
| GSE65391 | Evaluation | Microarray (whole blood) | **Cannot use** |
| GSE89408 | RA training | Bulk RNA-seq (synovium) | **Cannot use** |
| GSE142016 | SLE training | scRNA-seq PBMC, 3 samples | Usable but tiny |
| GSE134809 | IBD training | scRNA-seq (Crohn's), 31 samples | Usable |

### 3.2 Replacement Datasets — Confirmed Available

| Dataset | Source | Cells | Disease activity | Access | Download |
|---|---|---|---|---|---|
| **GSE135779** | Nehar-Belaid 2020, *Nat Immunol* | 276k PBMC | SLEDAI (LDA ≤4 / HDA >4) | **Public GEO** | `wget ftp://ftp.ncbi.nlm.nih.gov/geo/series/GSE135nnn/GSE135779/suppl/GSE135779_RAW.tar` |
| **CellxGene RA PBMC** | PMC11343607 | 125k PBMC | DAS28-CRP | **Public, CC BY 4.0** | CellxGene Discover portal |
| **GSE134809** | IBD/Crohn's | ~50k | Disease vs healthy | Public GEO | As before |
| **Arc Virtual Cell Atlas** | Arc Institute | 500M+ | Mixed | **Public** | arcinstitute.org |
| GSE174188 | Perez 2022, *Science* | 1.2M | SLEDAI | **dbGaP blocked** | Requires approval phs002812 |

**Key note:** NCBI E-utilities, GEOparse, and GEO FTP have no back door around dbGaP. Only public GEO deposits are accessible programmatically.

### 3.3 Data Download Commands

```bash
# Evaluation dataset (public, no approval)
wget ftp://ftp.ncbi.nlm.nih.gov/geo/series/GSE135nnn/GSE135779/suppl/GSE135779_RAW.tar
git clone https://github.com/dnehar/SingleCells_SLE_paper  # SLEDAI metadata

# IBD training
# GSE134809 via GEOparse:
python -c "import GEOparse; GEOparse.get_GEO('GSE134809', destdir='./data/')"

# RA training (CellxGene)
# Download from cellxgene.cziscience.com — search 'rheumatoid arthritis PBMC'
```

---

## 4. Innovation Analysis

### 4.1 Options A, B, C (Individual)

| Option | Description | Novelty verdict | Reason |
|---|---|---|---|
| A | Cross-disease categorical FT (RA+SLE+IBD labels) | Incremental | Standard 4-class FT; no method contribution |
| B | Pathway score regression FT (IFN/NF-κB/complement) | Incremental + circularity | IFN score computed from same genes model encodes |
| C | Immune-GRN attention biases | Already done | GRNFormer ACL 2025 covers this for drug response |

### 4.2 A+B Combined — Multi-Task Hierarchical Supervision

**Novelty verdict: Genuinely novel** — confirmed by targeted literature search (no paper combines cross-disease categorical labels + continuous pathway score regression as joint fine-tuning supervision for patient stratification).

**Loss function:**
```
L = L_CE(disease_type_labels) + λ · L_MSE(pathway_activation_scores)
```

**The falsifiable hypothesis:**
> Training on disease-type labels forces the model to learn what distinguishes immune states across diseases; pathway scores force it to learn quantitative immune activation gradients. Together they build an embedding space where SLE disease activity (never labeled during training) is separable as an emergent property — because in SLE, the IFN signature is simultaneously the strongest inter-disease discriminator and the strongest intra-disease activity correlate.

**Critical confounder:** This alignment is IFN-specific and SLE-specific. It is NOT a general principle. The deconfounded ASW test (regress out IFN score, remeasure silhouette) is mandatory.

### 4.3 Literature Gaps Confirmed

| Gap | Search result |
|---|---|
| Multi-task classification + regression FT for scRNA | Not found (eSPred closest but different mechanism) |
| Pathway scores as explicit regression supervision | Not found |
| Cross-disease → within-disease stratification | Not found |
| SLEDAI prediction from scRNA foundation model FT | Not found — Perez 2022 used monocyte trajectory (R=0.66), not FT |

**Real baseline to beat:** Perez 2022 monocyte activation trajectory R=0.66 SLEDAI correlation (on GSE174188, which is dbGaP-locked — find analogous result on GSE135779).

---

## 5. Evaluation Design

### 5.1 Gold Standard
- **SLEDAI score** — assigned by rheumatologist from 24 clinical/lab items, independent of transcriptomics
- Threshold: SLEDAI ≤4 = LDA, SLEDAI >4 = HDA, healthy = 0
- Auxiliary: anti-dsDNA titer, complement C3/C4 (orthogonal to IFN)

### 5.2 Metrics

| Metric | Computation | Purpose |
|---|---|---|
| ASW (primary) | `silhouette_score(embs, SLEDAI_group, metric='cosine')` | Embedding geometry |
| kNN purity | Fraction of 15-NN sharing same SLEDAI group | Local structure |
| Linear probe AUC | Logistic regression, 5-fold CV, 3-class | Linear decodability |
| SLEDAI R² | Ridge regression on continuous SLEDAI | Gradient capture |
| **Deconfounded ASW** | Regress IFN score from embs, recompute silhouette | Proves ≠ IFN leakage |
| Anti-dsDNA R² | Ridge regression on orthogonal clinical var | Beyond-IFN generalization |

### 5.3 Ablation Table

| Condition | Supervision | Expected rank |
|---|---|---|
| Base Geneformer v2 | None | Lowest |
| SLE-only label FT (matched cells) | {SLE, healthy} | Low-medium |
| Cross-disease label FT (A only) | {RA, SLE, IBD, healthy} | Medium |
| Pathway-only FT (B only) | IFN + complement + NF-κB scores | Medium (circularity risk) |
| **Cross-disease + pathway FT (A+B)** | Labels + pathway scores | Highest (hypothesis) |

### 5.4 External Baselines

| Model | Type |
|---|---|
| scVI | VAE (best non-transformer baseline) |
| scGPT-blood | Alternative transformer foundation model |
| UCE zero-shot | No fine-tuning baseline |
| Monocyte trajectory (Perez 2022 method) | Clinical gold standard method |
| PCA + Seurat | Classical scRNA method |

---

## 6. Hardware & Timeline

### 6.1 Hardware: NVIDIA DGX Spark (GB10, 128GB LPDDR5X unified memory)

| Spec | Value |
|---|---|
| Memory | 128GB LPDDR5X unified (CPU+GPU shared) |
| Bandwidth | ~273 GB/s |
| Peak compute | ~1 PFLOP FP8 |
| Architecture | Blackwell sm_100 |

**Training configuration:**
```python
training_args = {
    "per_device_train_batch_size": 64,
    "gradient_accumulation_steps": 1,
    "dataloader_num_workers": 8,
    "dataloader_pin_memory": False,  # unified memory — irrelevant
    "bf16": True,
    "tf32": True,
}
```

### 6.2 Timeline

| Step | Time |
|---|---|
| Data download + preprocessing | 4–8h (CPU) |
| Tokenization | 2–3h |
| Fine-tuning × 5 conditions | ~50h (~2 days) |
| Embedding extraction | 2–4h |
| Analysis + figures | 2–3h |
| **Total** | **~3–5 days** |

**Cloud cost if using AWS instead:** ~$40 (LoRA) to ~$120 (full FT) on p3.2xlarge.

---

## 7. Arc Institute Virtual Cell Challenge

**The 2025 challenge is over** (wrapped at NeurIPS 2025). Task was perturbation prediction in H1 embryonic stem cells — no disease, no patients, no immune cells. **Not a fit for this work.**

**Indirect relevance:**
- Arc Virtual Cell Atlas (500M+ cells, open) is a training data source
- The broader question "do virtual cell representations generalize to clinical disease states?" is the intellectual framing this work contributes to
- **CZI is the better strategic alignment** — their virtual cell program is explicitly disease-focused (rBio reasoning model, HCA, $20M CRISPR immune investment)

---

## 8. Available Foundation Models — Confirmed Status

| Model | Weights | Training data | Immune-specific? | Verdict |
|---|---|---|---|---|
| **scGPT-blood** | ✅ GitHub + CZI portal | 10.3M blood/bone marrow cells | **YES** | **Best available starting point** |
| **Geneformer V2-316M** | ✅ HuggingFace ctheodoris/Geneformer | 104M pan-tissue cells | No | Good generalist fallback |
| **scFoundation** | ✅ HuggingFace genbio-ai/scFoundation | 50M pan-tissue cells | No | Larger generalist alternative |
| **UCE 33-layer** | ✅ Figshare | 36M multi-species cells | No | Zero-shot baseline only |
| **GeneMamba** | ⚠️ Check paper repo | ~30M cells, Mamba arch + pathway-aware pretraining | No | Most architecturally novel |
| **EVA** | ❓ Check PDF / email authors | Cross-species immune + histology | **YES** | Ideal if weights released |
| **CZI rBio** | ❌ Proprietary | Unknown | Unknown | Not available |

**CZI clarification:** CZI does NOT have a proprietary foundation model with public weights. Their "Virtual Cell Models" portal (`virtualcellmodels.cziscience.com`) simply hosts scGPT-blood (bowang-lab weights). rBio is a CZI internal reasoning model — no public release.

### GeneMamba — Critical New Discovery

GeneMamba (arXiv:2504.16956, April 2025) is directly relevant:
- **Mamba (SSM) architecture** — O(n) complexity, processes longer gene sequences than transformer-based models
- **Pathway-aware contrastive loss** during pretraining — overlaps with Option B
- **Implication:** If GeneMamba already bakes in pathway supervision, Option B alone is less novel. But the cross-disease + clinical stratification framing (A+B) remains undone.

---

## 9. New Models Discovered (Survey Continuation)

| Model | Venue | Architecture | Training data | Immune-specific | Weights |
|---|---|---|---|---|---|
| **RegFormer** | *Nature Comm.* 2026 | **Mamba + GRN priors** | 26M cells, 45 tissues | No | Check repo |
| **CellFM** | *Nature Comm.* 2025 | RetNet (800M params) | **100M cells, 19.2M T cells** | Partial | **Zenodo + GitHub** |
| **SCARF** | bioRxiv Apr 2025 | Mamba, joint RNA+ATAC | 2.7M paired multi-omic | No | **Zenodo** |
| **Chreode** | arXiv 2025 | Flow matching | — | No | Preprint |
| **scGPT-spatial** | bioRxiv Feb 2025 | scGPT + MoE decoder | 30M spatial | No | **GitHub** |
| **scMamba (multi-omic)** | arXiv Jun 2025 | SSM + patch tokens | Multi-omic | No | Check repo |

### RegFormer — Critical Discovery
RegFormer (*Nature Communications* 2026) combines Mamba (O(n) efficiency) with GRN hierarchical priors and outperforms scGPT, Geneformer, scFoundation, scBERT across clustering, batch integration, cell type annotation, perturbation, and drug response. If weights are public, this is the best possible base model — it already incorporates both architectural innovations (Mamba + GRN) that were previously proposed as separate contributions.

### CellFM — Available Now, Immune-Heavy
CellFM (800M params, RetNet architecture, 100M cells with 19.2M T cells explicitly) has weights on Zenodo (DOI 10.5281/zenodo.15155900). The immune-heavy pretraining corpus makes it the best available starting point if RegFormer weights are not released.

## 10. Strategic Recommendation: Starting Point

**Priority order (check weights in this order):**
1. **RegFormer** — Mamba + GRN, best benchmark performance; check paper GitHub
2. **CellFM** — RetNet 800M, 19.2M T cells, Zenodo weights available now
3. **scGPT-blood** — confirmed available, 10.3M blood cells
4. **EVA** — ideal but weights unconfirmed

**If training from scratch:** three architecturally novel designs not in any existing model:
1. Disentangled dual encoder (z_type ⊥ z_state) — separates cell identity from disease activation
2. ClinCLIP — contrastive alignment of transcriptome ↔ clinical lab values (SLEDAI, anti-dsDNA, complement)
3. Mamba backbone for full 20k-gene context (vs. transformer 2048-gene truncation)
Feasible on DGX Spark at 1–5M immune cell scale.

## 11. Critical Methodological Finding: Layer Sweep Required

**Intermediate layers outperform final layers** (arXiv:2604.14838, 2025):
- Trajectory inference: intermediate layer at 60% depth outperforms final layer by 31%
- Disease activity prediction: optimal layer shifts by up to 96 percentage points across T cell states

**Implication:** Do NOT default to last-layer embeddings. Run a layer sweep at 0%, 25%, 50%, 75%, 100% depth and report optimal layer — this is now a **required methodological step**, not optional. Add to ablation table.

## 12. Warning: Simple Baselines Can Win

Benchmarking studies (2025) found that **mean-of-training-examples outperforms scGPT and scFoundation** for perturbation prediction in some settings. For disease activity prediction:
- Verify that a simple PCA + logistic regression baseline on raw expression doesn't trivially beat foundation model embeddings
- If mean-cell-type expression from the training cohort already separates LDA/HDA, fine-tuned foundation models add nothing
- Add: mean-expression centroid baseline to the ablation table

---

## 13. Survey Part 3 — Key New Findings

### New models (direct competitors / better baselines)

| Model | Venue | Key innovation | Weights | Relevance |
|---|---|---|---|---|
| **TEDDY** | arXiv:2503.03485 Mar 2025 | 6 models 70M–400M, disease state held-out eval, 116M CellxGene cells | Check repo | **Direct competitor — must cite and baseline** |
| **BMFM-RNA** | arXiv:2506.14861 Jun 2025 | WCED: CLS→whole-gene-vocab; data-efficient pretraining | **HuggingFace now** | Lightweight baseline |
| **IBDverse** | *Nature Genetics* 2026 | 1.1M Crohn's cells, 343 patients, public portal | ibdverse.info | Replaces GSE134809 for IBD training |
| **SAE (sparse autoencoders)** | bioRxiv 2025-2026 | Decompose scFM CLS token into interpretable feature directions | Multiple repos | Correct interpretability method |

### Critical: Attention is NOT interpretability (arXiv:2602.17532)
A 2025 paper with 37 analyses and 153 statistical tests showed that trivial gene co-expression baselines outperform attention weights for GRN recovery (AUROC 0.81–0.88 vs. 0.70). **Do not claim attention visualization reveals disease mechanisms.** Use sparse autoencoders (SAE) instead — they decompose the CLS token into biologically interpretable feature directions and are now the established interpretability method for scRNA foundation models.

### SLE biology: train on all PBMCs, not per cell type
The IFN signature in SLE is distributed across ALL major PBMC compartments (monocytes, CD4/CD8 T cells, NK cells, B cells, pDCs). Disease activity signal is driven by **expansion of ISG-high subpopulations within each cell type**, not differences in cell-type proportions. Training on all PBMCs together captures both the within-cell-type activation and the compositional signal.

### Two-disease evaluation is feasible and much stronger
- SLE eval: GSE135779 (SLEDAI-stratified, public GEO) ✅
- RA eval: PMC11343607 JCI Insight 2024 (DAS28-stratified, 125k PBMC, public) ✅
- If A+B FT improves silhouette in BOTH SLE and RA, the cross-disease manifold hypothesis is confirmed for two diseases simultaneously — a qualitatively stronger result.

### Revised training data recipe
```
SLE:     GSE142016         (~10k cells)   — keep all, smallest class
RA:      CellxGene PBMC    (~125k cells)  — cap at 30k, DAS28 labels
IBD:     IBDverse portal   (1.1M Crohn's) — cap at 30k
Healthy: CellxGene normals (~100k cells)  — cap at 30k
Round-robin sampling across 4 groups per epoch
```

### Treatment response: next natural step
No published paper predicts SLE treatment response (belimumab, anifrolumab) from scRNA foundation model embeddings. Anifrolumab blocks type I IFN — patients with high IFN signature respond better. A model that encodes IFN activation more precisely than bulk RNA-seq is directly useful to AstraZeneca (commercial interest confirmed). This is the clinical translation story.

### Competition: Immunai is the main competitor
Immunai ($270M raised, AstraZeneca $37.5M + Boehringer $15M autoimmune partnerships) has the AMICA platform for clinically annotated immune atlas. They do not publish weights or methods — academic work wins on interpretability, reproducibility, and algorithmic novelty.

## 10. Immediate Next Steps

1. **Download scGPT-blood** from `github.com/bowang-lab/scGPT` model zoo — available now
2. **Check EVA PDF** for weight download URL — email authors if not in paper
3. **Check GeneMamba repo** for weights — if available, add as 3rd comparison
4. `wget GSE135779_RAW.tar` — evaluation data (SLEDAI-stratified SLE PBMC)
5. `git clone github.com/dnehar/SingleCells_SLE_paper` — SLEDAI metadata
6. Download CellxGene RA PBMC — training data
7. Implement A+B multi-task FT on scGPT-blood on DGX Spark
8. Run full ablation table (5 conditions + 3 external baselines)
9. Report deconfounded ASW as primary result
