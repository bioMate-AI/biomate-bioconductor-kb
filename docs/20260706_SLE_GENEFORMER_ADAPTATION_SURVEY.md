# SLE Geneformer Adaptation — Full Survey & Proposal
**Date:** 2026-07-06  
**Topic:** Adapting single-cell foundation models for SLE patient stratification by disease activity  
**Hardware context:** NVIDIA DGX Spark, GB10 Grace Blackwell, 128GB LPDDR5X unified memory

---

## 1. Task Definition (Original)

From `docs/20260706_SLE_BANCHEREAU_PILOT_ELABORATION.md`, Task 3:

> Fine-tune Geneformer v2 on GSE89408 (RA) + GSE142016 (SLE) + GSE134809 (IBD). Run base and fine-tuned embeddings on GSE65391 (SLE PBMC, Banchereau 2016). Compare silhouette score of 3 patient clusters (low disease activity, high disease activity, healthy) in embedding space.

**Critical finding:** The original dataset plan is broken.
- GSE65391 = microarray (Illumina HumanHT-12 V4.0, whole blood) — Geneformer requires scRNA-seq
- GSE89408 = bulk RNA-seq (synovial tissue) — not single-cell

---

## 2. Corrected Dataset Plan

| Role | Original | Replacement | Access |
|---|---|---|---|
| RA training | GSE89408 (bulk, blocked) | CellxGene RA PBMC — 125k cells, DAS28 labels | Free, CC BY 4.0 |
| SLE training | GSE142016 (scRNA, 3 samples) | Keep + Arc Virtual Cell Atlas supplement | Free |
| IBD training | GSE134809 (Crohn's, 31 samples) | Keep | Free, GEO |
| Evaluation | GSE65391 (microarray, blocked) | **GSE135779** (Nehar-Belaid 2020, 276k cells, SLEDAI) | **Free, GEO today** |

### Download commands (no approval required)
```bash
# Evaluation dataset — Nehar-Belaid 2020, Nature Immunology
wget ftp://ftp.ncbi.nlm.nih.gov/geo/series/GSE135nnn/GSE135779/suppl/GSE135779_RAW.tar
git clone https://github.com/dnehar/SingleCells_SLE_paper  # SLEDAI metadata CSVs

# RA training — CellxGene (download via CELLxGENE Discover interface or API)
# IBD training
# GEOparse for GSE134809:
python -c "import GEOparse; GEOparse.get_GEO('GSE134809', destdir='./data/')"
```

### GSE135779 (Nehar-Belaid 2020) details
- 276k PBMCs (discovery) + 132k (validation)
- 33 childhood SLE + 8 adult SLE + 17 healthy controls
- SLEDAI scores → LDA (≤4) vs HDA (>4) vs healthy
- Nature Immunology 2020
- Raw FASTQs: dbGaP phs002048 (not needed — processed MTX is public)
- Interactive explorer: https://dnehar.shinyapps.io/cSLE_app/

---

## 3. Survey Part 1: Standard Bio-LLM Adaptation Methods

### 3.1 Geneformer (Official Fine-Tuning)
- **Paper:** Theodoris et al., *Nature* 2023 + v2 2024
- **Architecture:** 6-layer transformer, 256M params, trained on 95M single-cell transcriptomes
- **Input:** Rank-ordered top-2048 genes per cell (Ensembl IDs as tokens, no expression values)
- **Fine-tuning modes:** Cell classification (CrossEntropy), Cell/Gene regression (MSE)
- **Hyperparams:** LR=5e-5, batch=12, epochs=10–15, freeze first 2 layers for cross-tissue
- **Time on A100:** ~30 min for 50k cells; ~4h for 500k cells
- **Code:** `pip install geneformer`, HuggingFace `ctheodoris/Geneformer`

### 3.2 scGPT (Cui et al., Nature Methods 2024)
- Generative transformer, 33M cells, handles expression values (continuous binned)
- Multi-task: GEPC reconstruction loss + classification loss
- `scGPT_blood` checkpoint available — pretrained on blood/PBMC specifically
- Code: github.com/bowang-lab/scGPT

### 3.3 LoRA / Adapter (scPEFT, Chen et al., bioRxiv 2024)
- LoRA rank=8–16, target `query, value` attention matrices
- 98% parameter reduction, within 1–2pp of full FT
- 8GB VRAM instead of 40GB
- Code: github.com/HelloWorldLTY/scPEFT

### 3.4 Supervised Contrastive (SSL4scRNA, Bioinformatics 2024)
- SimCLR-style, disease state as label, NT-Xent loss, batch 256
- Directly optimizes embedding geometry — best fit when silhouette score is the metric

### 3.5 UCE (Rosen et al., Nature Methods 2025)
- Uses ESM2 protein embeddings as gene vocabulary
- Zero-shot across 1000 species; no fine-tuning needed
- Uses silhouette score and LISI as evaluation metrics

### 3.6 scFoundation (Hao et al., Nature Methods 2024)
- "Read-depth augmentation" pretraining (masks to simulate shallow sequencing)
- Partial layer freezing: freeze early layers, fine-tune late layers (95% of full FT, 40% less memory)

---

## 4. Survey Part 2: Novel 2024–2025 Approaches

### 4.1 Drug-Conditional Adapter (ICLR 2025, arXiv:2412.13478)
- Freeze 99%+ of model; inject small condition-specific adapter (<1% params)
- Adapter conditioned on perturbation identity (drug structure → fingerprint)
- Zero-shot generalization to unseen drugs/cell lines
- **Task 3 translation:** Replace drug condition → disease-state condition (RA/SLE/IBD)

### 4.2 CellRefine — Prototype-Guided Post-Pretraining (arXiv:2605.07938, May 2025)
- Intermediate training stage between pretraining and fine-tuning
- Marker-gene-set-guided masked LM + cell ontology similarity regularization
- Reshapes embedding geometry before downstream FT
- **Directly relevant:** improves cluster purity under covariate shift

### 4.3 GRNFormer — GRN-Injected Attention (ACL 2025, arXiv:2503.01682)
- Injects gene regulatory network edges as attention biases during FT
- +9.6% AUC on drug classification vs Geneformer baseline
- Immune GRN sources: DoRothEA, DICE eQTLs, ENCODE ChIP-seq

### 4.4 EVA — Universal Immune System Model (arXiv:2602.10168, Feb 2026)
- First cross-species multimodal immunology foundation model
- 39-task evaluation suite including patient stratification and disease activity
- **Most directly relevant model** — if weights release, use as base instead of Geneformer
- Weights not yet public

### 4.5 scMMGPT — Text-Conditioned Cell Embeddings (arXiv:2503.09427, Mar 2025)
- Joint pretraining on (cell expression, biological text) pairs, 27M cells
- Can condition on free text: "SLE high-disease-activity PBMC, elevated IFN"
- Most experimental, highest upside

### 4.6 PT-RAG — Inference-Time Retrieval (ICLR 2025, arXiv:2603.07233)
- Retrieve K most similar cells from reference at inference — no weight updates
- Good zero-shot upper bound baseline

### 4.7 Cell-o1 — RL Batch Reasoning (Bioinformatics 2025, arXiv:2506.02911)
- RL with batch-level rewards; model assigns cell types to whole batches
- +73% over GPT-o1 on CellPuzzles benchmark

### 4.8 scRAG — KG + Cell Retrieval (ACL 2025)
- Disease–CellType + Gene–CellType knowledge graphs + hybrid RAG
- Code: github.com/YuZhiyin/scRAG

---

## 5. Innovation Assessment

### Option A: Cross-Disease → Intra-Disease Transfer
**Standard 4-class classification FT. Verdict: Incremental.**
- Experimental framing is novel (train on disease type, evaluate on activity level)
- No method contribution — just an application
- Critical confounder: GSE142016 (SLE) in training + GSE135779 (SLE) in test → potential data leakage; confirm patient-level non-overlap
- Venue: Cell Systems, Nature Communications (findings paper)

### Option B: Pathway-Supervised Regression
**Incremental + circularity risk. Verdict: Do not use alone.**
- IFN score is computed from the same genes Geneformer encodes → circular
- Reviewer will reject: "training model to predict linear transformation of its own input"
- Rescue: deconfound by regressing out IFN score and remeasuring silhouette

### Option C: Immune-GRN Attention Bias
**Already done. Verdict: Do not publish standalone.**
- GRNFormer (ACL 2025) covers this. Domain change only, not method change.

### Option A+B Combined: Multi-Task Hierarchical Supervision ✅ NOVEL
**The publishable version.**

No existing paper combines:
1. Categorical cross-disease labels (inter-disease diversity)  
2. Continuous pathway activation scores (intra-disease gradient)

as joint supervision for foundation model FT targeting patient stratification.

**Multi-task loss:**
```
L = L_CE(disease_type) + λ · L_MSE(pathway_scores)
```

**Why it resolves A and B weaknesses individually:**
- A alone: no method contribution
- B alone: circularity with IFN score
- A+B: disease-type labels prevent model collapsing to IFN detection; pathway scores provide quantitative gradation categorical labels cannot

**Falsifiable claim:** FT(A+B) silhouette > FT(A only) > FT(B only) > base

---

## 6. Literature Check — Existing Work Overlap

| Paper | Overlap | Verdict |
|---|---|---|
| eSPred (bioRxiv May 2025) | Pathway-informed FT as architectural constraints | Mechanism differs; no cross-disease; cite and differentiate |
| scKGBERT (Genome Biology 2025) | KG-augmented multi-task, 12 tasks | PPI graph not pathway scores; no disease activity |
| iScience 2025 | 1.3M-cell multi-autoimmune descriptive atlas | Analysis only, no FT; critical: already has your training data analyzed |
| Perez 2022 (Science) | Monocyte trajectory → SLEDAI R=0.66 | **The real baseline to beat** — same dataset GSE174188 (dbGaP locked) |
| scTransformer (arXiv Jun 2025, 2606.09558) | GRN attention for snRNA-seq | Overlaps Option C only |

**Gap confirmed:** No paper does cross-disease categorical + pathway regression jointly for patient stratification.

---

## 7. Gold Standard and Evaluation

### Gold Standard
**SLEDAI (SLE Disease Activity Index)** — clinician-assigned from 24 clinical+lab items, independent of transcriptomics. SLEDAI ≤4 = LDA, >4 = HDA. Standard in every SLE clinical trial.

### Primary Metric: ASW (Average Silhouette Width)
```python
from sklearn.metrics import silhouette_score
sil = silhouette_score(embeddings, sledai_group_labels, metric='cosine')
```

### Full Evaluation Suite

| Metric | Purpose |
|---|---|
| ASW (cosine) | Embedding geometry — primary |
| kNN purity (k=15) | Local structure quality |
| Linear probe AUC (3-class, 5-fold CV) | Linearly decodable disease activity |
| SLEDAI R² (ridge regression) | Continuous gradient prediction |
| Deconfounded ASW | Regress out IFN score first — proves improvement ≠ IFN leakage |
| Anti-dsDNA R² | Orthogonal clinical variable — proves generalization beyond IFN axis |

### Baselines

**Ablations (mandatory):**
1. Base Geneformer v2 (no FT)
2. SLE-only label FT (matched cell count)
3. Cross-disease label FT only (A)
4. Pathway-only FT (B)
5. Cross-disease + pathway FT (A+B) ← main claim

**External baselines:**
- scVI (VAE)
- scGPT-blood FT
- UCE zero-shot
- Harmony (linear batch correction)
- PCA + Seurat (classical)
- **Perez 2022 monocyte trajectory (R=0.66)** ← the published bar to beat

---

## 8. Core Assumptions and Risks

| Assumption | Risk Level | Failure mode | Test |
|---|---|---|---|
| IFN axis aligns inter-disease and intra-SLE activity | Medium | IFN leakage only | Deconfounded ASW |
| RA PBMC contributes signal (not just noise) | High | RA PBMC signature too weak | Ablation: remove RA |
| Pathway scores not cell-type confounded | High | Monocytes have high complement regardless of disease | Compute scores within cell type |
| 200k cells reshapes 95M-cell pretrained model | Medium | Delta within noise | Learning curve vs. training cells |
| GSE142016 (3 samples) represents SLE | High | Underpowers SLE representation | Supplement with Arc Virtual Cell Atlas |
| Multi-task loss balance non-degenerate | Low | Standard hyperparameter issue | Grid search λ ∈ {0.01, 0.1, 1.0} |

---

## 9. Arc Institute Virtual Cell Challenge

**The 2025 challenge is over (wrapped up at NeurIPS 2025).**
- Task: perturbation prediction in H1 embryonic stem cells (CRISPRi knockdown)
- Metric: PDS, DES, MAE
- Winner: scFoundation-based hybrid + protein embeddings
- **Direct relevance to proposed work: none** — wrong task, wrong biology

**Indirect relevance (ongoing Arc Virtual Cell Initiative):**
- Their open question: "do virtual cell representations generalize to clinically-meaningful disease states?" — exactly what this project tests
- Arc Virtual Cell Atlas: 500M+ cells, 21 organisms, 72 tissues, openly available → candidate training data source

**Better strategic fit: CZI**
- rBio reasoning model, HCA, $20M CRISPR immune disorder investment — all disease-focused
- Proposed SLE work fits CZI's roadmap more naturally

---

## 10. Hardware: NVIDIA DGX Spark (GB10, 128GB)

| Spec | Value |
|---|---|
| Architecture | Grace Blackwell (sm_100) |
| Memory | 128GB LPDDR5X unified (CPU+GPU shared) |
| Memory bandwidth | ~273 GB/s |
| Peak AI compute | ~1 PFLOP FP8 |
| Key difference from datacenter GPU | Unified memory vs. dedicated HBM → ~2–3× slower training throughput |

**Revised time estimates:**
- Full FT per condition (Geneformer, 200k cells): 8–12h
- All 5 ablation conditions: ~50h (~2 days)
- Full experiment end-to-end: 3–5 days, zero cloud cost

**Optimal training config:**
```python
training_args = {
    "per_device_train_batch_size": 64,
    "gradient_accumulation_steps": 1,
    "dataloader_num_workers": 8,
    "dataloader_pin_memory": False,  # unified memory — pinning irrelevant
    "bf16": True,                    # Blackwell native
    "tf32": True,
}
```

---

## 11. Open Strategic Question (Under Investigation)

**Why start from Geneformer (generalist) rather than an immune-specific foundation model?**

Key candidates being investigated:
- **EVA** (arXiv:2602.10168) — immunology foundation model, weights not yet public
- **scGPT-blood** — blood/PBMC-specific checkpoint, may be publicly available
- **CZI virtual cell model** — unknown availability
- **Arc Virtual Cell Atlas companion model** — unknown

Starting from an immune-specific model would:
- Provide higher baseline performance
- Require less fine-tuning data to achieve target-domain adaptation
- Potentially reduce the novelty of the adaptation work (less gap to close)
- Change the paper's contribution from "cross-disease FT improves generalist" to "disease-specific FT improves immune model"

Results of this search will determine whether the innovation story changes.

---

## 12. Recommended Next Steps

1. **Check Arc Virtual Cell Atlas** — if RA/SLE/IBD PBMC present, replaces all data access problems
2. **Download GSE135779** today — evaluation set, publicly available now
3. **Download CellxGene RA PBMC** — free training data with DAS28 labels
4. **Confirm SLEDAI column names** in `dnehar/SingleCells_SLE_paper` GitHub metadata CSVs
5. **Check EVA weights** and scGPT-blood checkpoint availability
6. **Apply for dbGaP phs002048** as backup for full Nehar-Belaid raw data
7. **Start A+B implementation** with available data; use held-out GSE135779 subset as temporary eval
8. **Target venue:** Nature Communications or Cell Systems; Nature Methods if cross-disease generalization is strong

---

## 13. Key References

| Paper | Venue | ArXiv/DOI | Relevance |
|---|---|---|---|
| Theodoris et al. | Nature 2023 | — | Geneformer original FT recipe |
| Cui et al. | Nature Methods 2024 | — | scGPT FT recipe + scGPT-blood |
| Chen et al. | bioRxiv 2024 | — | scPEFT / LoRA for scRNA |
| Drug-conditional adapter | ICLR 2025 | 2412.13478 | Condition adapter pattern |
| CellRefine | arXiv 2025 | 2605.07938 | Prototype-guided post-pretraining |
| GRNFormer | ACL 2025 | 2503.01682 | GRN attention bias |
| EVA | arXiv 2026 | 2602.10168 | Immune foundation model |
| scMMGPT | arXiv 2025 | 2503.09427 | Text-conditioned cell embeddings |
| PT-RAG | ICLR 2025 | 2603.07233 | Retrieval-augmented perturbation |
| Cell-o1 | Bioinformatics 2025 | 2506.02911 | RL batch cell reasoning |
| scRAG | ACL 2025 | — | KG + retrieval annotation |
| eSPred | bioRxiv 2025 | 10.1101/2025.05.14.654052 | Pathway-informed FT (closest overlap) |
| scKGBERT | Genome Biology 2025 | — | KG multi-task FT |
| iScience 2025 | iScience | — | 1.3M-cell multi-autoimmune atlas |
| Nehar-Belaid et al. | Nature Immunology 2020 | — | GSE135779 evaluation dataset |
| Perez et al. | Science 2022 | — | SLEDAI R=0.66 baseline (GSE174188, dbGaP) |
| Rosen et al. | Nature Methods 2025 | — | UCE zero-shot |
