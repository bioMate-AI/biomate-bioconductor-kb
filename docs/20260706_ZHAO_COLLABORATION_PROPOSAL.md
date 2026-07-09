# Research Collaboration Proposal
## Disease-State-Resolved GWAS Cell-Type Attribution
### BioMate × Zhao Lab (UTHealth Houston)

**Date:** 2026-07-06

---

## The Problem with scGWAS as It Stands

scGWAS maps GWAS loci to cell types by testing whether a variant's gene set is enriched in the transcriptomes of a given cell type. The method works. The limitation is implicit in the design: all cells annotated as "Treg" are treated as a single population. The reference panel is a static atlas.

In autoimmune disease this is wrong. A Treg from an SLE patient during a SLEDAI-14 flare is transcriptionally, functionally, and epigenetically different from a Treg in the same patient during SLEDAI-2 remission. If PTPN22 rs2476601 operates through Tregs, the current answer — "Treg / naïve CD4+ T cells" — tells you the cell type but not *which state* of that cell type. That distinction matters for drug timing, biomarker design, and mechanistic interpretation.

No current method resolves GWAS loci to cell type × disease-activity state simultaneously.

---

## The Proposed Innovation

Train a disease-activity-aware single-cell foundation model on a multi-disease IFN-spectrum cohort (SLE, pSS, JDM, SSc, IBD, T1D, AS — all PBMC scRNA-seq, 8 diseases). The model learns embeddings where position in embedding space encodes both cell identity and disease activation state, jointly, via a two-head multi-task objective:

```
L = CrossEntropy(disease_type_label) + λ · MSE(IFN_pathway_activation_score)
```

This forces the encoder to simultaneously represent what cell it is and how activated that cell is in a disease context — something a model trained on cell type labels alone cannot do.

Use the trained embeddings as the reference panel in scGWAS in place of the standard static atlas. The scGWAS enrichment test then becomes: is this variant's gene set enriched in **IFN-high Tregs** versus **IFN-low Tregs**, or is the enrichment state-indifferent?

The output is not "PTPN22 → Treg." It is: "PTPN22 → IFN-high Treg (SLE flare, SLEDAI >10); effect absent in IFN-low Treg (remission)."

---

## Why This Is Novel

**What scGWAS currently cannot do:**
- Distinguish activated vs. quiescent states of the same cell type
- Identify whether a GWAS locus is state-specific or constitutively expressed in a lineage
- Connect genetic risk to the specific disease context in which that risk is expressed

**What the published foundation model literature currently misses:**
- Disease-state-aware cell embeddings trained on a multi-disease IFN-spectrum design (existing models train on healthy atlas data or single-disease)
- Connection between single-cell embeddings and GWAS variant annotation

**The combination produces a new capability:** GWAS variant → cell type × disease-activity state. This is downstream-actionable — it tells you not just what to target but *when* and *in whom* to target it.

---

## Concrete First Experiment

**Variant:** PTPN22 rs2476601 (SLE/RA, p = 3.75 × 10⁻¹⁶⁸ in Ishigaki 2022)  
**Reference dataset:** GSE135779 — 276k PBMC from SLE patients with SLEDAI scores (Nehar-Belaid 2020, *Nat Immunol*)  
**Foundation model base:** Geneformer V2-316M  
**Comparison:** scGWAS output using (a) standard static atlas vs. (b) disease-state-stratified embeddings from fine-tuned model

**Expected output:**
- Standard atlas: PTPN22 → Treg (replicates Jia et al. *Genome Biology* 2022)
- Disease-state-stratified: PTPN22 → IFN-high Treg (SLEDAI ≥8) with state-specificity score

**Falsification condition:** if PTPN22 enrichment is identical across IFN-high and IFN-low Tregs, the hypothesis that PTPN22 operates through disease-activated cells fails — and that is also a publishable result (constitutive rather than state-specific risk).

---

## Division of Contributions

**Zhao Lab:**
- scGWAS methodology and modification to accept external embedding-based reference panels
- GWAS summary statistics expertise and locus curation
- Domain review of cell-type × disease-state assignments
- Authorship on the method extension paper

**BioMate:**
- Multi-disease IFN-spectrum foundation model training (8 diseases, all data already staged on S3)
- Construction of disease-state-stratified reference panels from the fine-tuned model
- AWS Batch compute for training and scGWAS runs
- Integration into BioMate's workflow system so the full chain (GWAS summary stats → disease-state-resolved cell annotation) is reproducible via a single session

**Data (already staged at `s3://galaxy-cloud-data-1760241377/research/sle-autoimmune/`):**

| Dataset | Disease | N cells | Activity measure |
|---------|---------|---------|-----------------|
| GSE135779 | SLE PBMC | 276k | SLEDAI (LDA ≤4 / HDA >4) |
| GSE142016 | SLE PBMC | small | disease/healthy |
| GSE134809 | IBD PBMC | ~50k | disease/healthy |
| GSE157278 | pSS PBMC | ~30k | disease/healthy |
| GSE190684 | JDM PBMC | ~40k | disease/healthy |
| GSE195452 | SSc PBMC | ~60k | disease/healthy |
| GSE221297 | T1D PBMC | ~50k | disease/healthy |
| GSE232131 | AS PBMC | ~30k | disease/healthy |

---

## POC Timeline (DGX Spark, 128 GB)

| Week | Work | Output |
|------|------|--------|
| 1 | Preprocess 8 GEO datasets → Geneformer tokenized format; compute IFN scores | `sle_ifn.dataset` ready for training |
| 2 | Zero-shot probing: extract layer-12 embeddings from pre-trained Geneformer V2; UMAP + linear probe AUC for SLEDAI LDA vs HDA | Baseline AUC; UMAP figure |
| 3 | Fine-tune with A+B multi-task loss on 7 training diseases; evaluate on GSE135779 held-out | Fine-tuned AUC; embedding geometry |
| 4 | Construct disease-state-stratified reference panels; run scGWAS on Ishigaki 2022 RA GWAS with both standard and new panels | State-resolved cell-type attribution table |
| 5 | Deconfounded ASW; disentanglement test (z_type ⊥ z_state); PTPN22 state-specificity score | Publication figure set |

---

## Why This Is Worth a Zhao Lab Collaboration (Not Just Tool Integration)

The existing proposal — wrapping turep, scGWAS, ImmuneApp in BioMate workflows — offers Zhao's lab operational convenience. That is a weak reason for a PI with 35k citations to engage.

This proposal offers co-authorship on a methodological extension of scGWAS with a new claim: that GWAS loci can be mapped to disease-activity states, not just cell types. That extension requires BioMate's multi-disease training infrastructure and their scGWAS methodology in equal measure — neither party can publish this alone.

The BioMate platform benefit is real but secondary: once the method is built, the full chain (GWAS → disease-state-resolved attribution → druggability → ADMET → IND) runs in a single BioMate session. That is the demo for the Zhao Lab call. But it is not the reason to start the collaboration.

---

## Publication Target

*Genome Biology* or *Nature Communications* — consistent with Zhao lab's prior scGWAS publication (Jia et al. *Genome Biology* 2022, PMC9575201) and the methodological scope of the contribution.

---

## Open Questions Before First Meeting

1. Does Zhao lab have additional unpublished single-cell data from autoimmune patients that would expand the training set beyond the 8 public GEO datasets?
2. Is the scGWAS codebase modular enough to swap the reference panel, or does it require architectural changes to accept embedding-based panels?
3. What additional GWAS loci beyond PTPN22 should the first experiment cover? (Candidates: TYK2, IL6R, STAT4, IRF5 — all IFN-pathway-adjacent.)
4. Is there appetite to extend beyond RA/SLE to the full IFN spectrum (pSS, JDM, SSc) in a follow-up paper, or constrain the first paper to SLE/RA?
