# Single Cell Coverage & Virtual Cell Analysis
**Date:** 2026-05-04  
**Session:** Coverage audit + improvement plan + test results

---

## Part 1 — Virtual Cell: Full Test Results

### Unit Tests (13/13 passing)

| # | Workflow | Test Case | Result | Key Metric |
|---|----------|-----------|--------|------------|
| 1 | `cipa_cardiac_safety_ode` | hERG IC50=30nM, Cmax=100nM | ✅ HIGH | APD90=363ms, qNET=−21.9 |
| 2 | `cipa_cardiac_safety_ode` | Verapamil-like balanced blocker | ✅ INTERMEDIATE | 2× hERG margin escalation |
| 3 | `ode_signaling_simulation` | MAPK MEK inhibitor (trametinib) | ✅ 78.6% inhibition | EC50_func computed |
| 4 | `ode_signaling_simulation` | BCL2_APOPTOSIS venetoclax | ✅ −10.8% (CASP3 activated) | Inverse pathway correct |
| 5 | `metabolic_flux_fba` | Hepatocyte Complex I+BSEP | ✅ DILI score >0.2 | Cascade correct |
| 6 | `metabolic_flux_fba` | Cardiomyocyte Complex III | ✅ ATP impairment >0% | Cascade fix applied |
| 7 | `transcriptomic_moa_lincs` | MYC+CDK4 up, TP53 down (mimic) | ✅ Hits returned | BCL2/BET pathway matched |
| 8 | `gears_perturbation_prediction` | MYC KO → CDK4/CCND1/E2F1 down | ✅ Target genes downregulated | Network propagation correct |
| 9 | `gears_perturbation_prediction` | KRAS+BRAF double KO epistasis | ✅ Combo + GI section | Bliss epistasis scored |
| 10 | `cpa_drug_combination_synergy` | Trametinib + palbociclib | ✅ Valid synergy class | Bliss/ZIP/HSA all computed |
| 11 | `physicell_tumor_tgi` | Erlotinib NSCLC 84 days | ✅ TGI>0, RECIST set | Simeoni ODE stable |
| 12 | `virtual_patient_cohort` | 500 patients PopPK PTA | ✅ PTA∈(0,1), 500+hdr rows | All 5 special pops scored |
| 13 | `transcriptformer_cell_state` | MYC+CDK4+MKI67 high expression | ✅ Cancer cells classification | Coverage weighting correct |

### Chain Tests (5/5 passing)

| Chain | Steps | Result | Output |
|-------|-------|--------|--------|
| ADMET → CiPA | hERG IC50 → CiPA ODE | ✅ | TdP=INTERMEDIATE |
| RNA-seq → LINCS | DESeq2 DEGs → CMap | ✅ | BCL2/BET pathway matched |
| MAGeCK → GEARS → LINCS | CRISPR hits → perturbation → drug | ✅ | 3-step data flow verified |
| PBPK → TGI | Cmax/AUC → Simeoni ODE | ✅ | TGI=100%, SD prognosis |
| ADMET+PBPK → PopPK | CL/Vd/F → Monte Carlo | ✅ | opt=200mg, PTA=83% |

### Bugs Fixed During Testing

1. **metabolic_flux_fba Complex III**: `atp=0` for E3 → Complex III block had no ATP impact. Fixed: E3 gets virtual `atp=+1.0`, `DRUG_EFFECTS` cascades `fb_ciii` to E1+E3+E5.
2. **ode_signaling_simulation BCL2**: Venetoclax should activate CASP3, not inhibit it. Fixed: `BCL2_APOPTOSIS` inverse pathway with inhibitory ODE coupling `dX_BAX ∝ stim × (1 − X_BCL2)`.
3. **transcriptformer_cell_state stem cell marker**: CDKN1A in "down" list inflated stem cell score when cancer cells had low p21. Fixed: CDKN1A moved to "up" (quiescent stem cells have high p21); added coverage-weighting to score function.

---

## Part 2 — Single Cell Coverage Audit

### What BioMate Has (34 workflows)

| Category | Workflows | Coverage |
|----------|-----------|---------|
| Core preprocessing | nf-core/scrnaseq (Cell Ranger, STARsolo, Kallisto/Bustools) | ✅ Strong |
| Downstream analysis | Seurat (R), Scanpy (Python), Monocle, scVI, Harmony | ✅ Strong |
| Trajectory/velocity | Monocle3, RNA velocity (via scrnaseq) | ✅ Good |
| Spatial (probe-based) | nf-core/spatialvi (10x Visium), nf-core/spatialxe (Xenium) | ✅ Good |
| Multi-modal annotation | CITE-seq downstream (CiteFuse), scRepertoire, nipalsMCIA | 🟡 Partial |
| Perturbation | state_perturbation_prediction | 🟡 One workflow |
| Doublet/QC | Not dedicated — integrated in scrnaseq | 🟡 Hidden |

### Coverage Gaps Identified

| Gap | Priority | What's Missing | Instrument/Platform |
|-----|----------|----------------|---------------------|
| **CITE-seq preprocessing** | P1 | CITE-seq-Count / kite + ADT matrix | 10x Chromium (protein + RNA) |
| **10x Multiome** | P1 | Joint RNA+ATAC embedding, WNN clustering | 10x Chromium Next GEM Multiome |
| **BD Rhapsody** | P2 | BD Seven Bridges pipeline / rhapsody python | BD Biosciences Rhapsody |
| **Parse Biosciences (split-seq)** | P2 | parsetools / pipe-line | Parse Evercode WT |
| **MERFISH / seqFISH** | P3 | spatialDE, Giotto for image-based spatial | Vizgen MERSCOPE, 10x Xenium |
| **Doublet detection** | P1 | DoubletFinder / Scrublet standalone | All platforms |
| **scATAC-seq dedicated** | P2 | ArchR / Signac standalone pipeline | 10x ATAC |
| **Proteomics+RNA (REAP-seq)** | P3 | Combined mass spec + scRNA | High-throughput |

### Instrument → BioMate Connection Map

| Instrument | Data Type | nf-core Pipeline | BioMate Status |
|------------|-----------|-----------------|----------------|
| 10x Chromium 3' / 5' | scRNA-seq | nf-core/scrnaseq | ✅ Available (id=12777) |
| 10x Visium | Spatial RNA | nf-core/spatialvi | ✅ Available (id=12783) |
| 10x Xenium | Spatial imaging | nf-core/spatialxe | ✅ Available (id=12784) |
| 10x Multiome | RNA + ATAC | nf-core/multiome | 🔴 Not yet added |
| 10x Chromium (CITE-seq) | RNA + protein | nf-core/scrnaseq --protocol CITE | 🔴 No dedicated workflow |
| BD Rhapsody | scRNA-seq | custom rhapsody pipeline | 🔴 Not present |
| Parse Biosciences | scRNA-seq | parsetools | 🔴 Not present |
| Smart-seq2 / Smart-seq3 | Full-length scRNA | nf-core/scrnaseq --protocol smartseq | 🟡 Covered by scrnaseq |
| Fluidigm C1 | Full-length scRNA | nf-core/scrnaseq | 🟡 Covered by scrnaseq |
| MERFISH (Vizgen MERSCOPE) | Spatial imaging | Giotto / spatialDE | 🔴 No pipeline |
| Oxford Nanopore (single-cell) | Long-read scRNA | nf-core/nanoseq | 🟡 Partial |

---

## Part 3 — Improvements Built (2026-05-04)

### New Single Cell Workflows

| ID | Name | Covers |
|----|------|--------|
| TBD | `cite_seq_preprocessing` | CITE-seq-Count + Seurat WNN, ADT normalization |
| TBD | `multiome_rna_atac` | 10x Multiome joint WNN, LSI+PCA, peak-to-gene |
| TBD | `bd_rhapsody_scrna` | BD Seven Bridges + quality filtering |
| TBD | `parse_split_seq_scrna` | Parse Biosciences Evercode processing |
| TBD | `scrna_doublet_qc` | DoubletFinder + Scrublet + quality thresholds |
| TBD | `merfish_spatial_analysis` | Image-based spatial: segmentation + expression |

### Extended Virtual Cell Tests

- All 8 ODE signaling pathways validated
- CiPA boundary conditions: LOW/INTERMEDIATE/HIGH thresholds
- Adversarial inputs: null IC50s, extreme Cmax, zero stimulus
- Metabolic FBA for all 4 cell types
- Virtual patient with all covariate subgroups
- Param prefill benchmark: virtual_cell_params category

---

## Open Items

| Item | Notes |
|------|-------|
| GPU image build + push | `docker buildx build --platform linux/amd64 -t .../virtual-cell-gpu:1.0 --push` |
| nf-core/multiome description patches | Need to add to routing patch script |
| MERFISH/seqFISH — no nf-core pipeline yet | Use Giotto or spatialDE directly |
| Spatial imaging: image segmentation step | Requires cellpose/stardist Docker |
| BD Rhapsody: proprietary demux | Seven Bridges platform or open-source alternative |
