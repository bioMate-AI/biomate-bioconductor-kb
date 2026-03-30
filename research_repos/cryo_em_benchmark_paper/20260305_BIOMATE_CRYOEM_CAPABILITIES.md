# BioMate Cryo-EM & Structural Biology Capabilities
**Date:** 2026-03-05
**Audience:** Academic structural biologists, cryo-EM facility directors and staff, cell biology labs doing in-situ cryo-ET, and collaborative drug discovery groups using structure-based design
**Document type:** Platform capability overview for collaboration discussions and Paper B (cryo-EM benchmark paper) context

---

## 1. Executive Summary

BioMate is an AI-powered structural biology platform that executes reproducible, containerized Nextflow (nf-core DSL2) workflows covering the complete cryo-EM/ET pipeline — from raw movie stack import through single-particle reconstruction, post-processing, model building, and structure-based drug design. Every stage is governed by an evidence-graded QC layer (GOLD / SILVER / BRONZE) that blocks or flags poor-quality data before it propagates to expensive downstream refinement or drug design steps, directly addressing the silent QC failure modes — motion blur, CTF estimation errors, preferential orientation, and junk particle contamination — that are the leading causes of failed SPA projects. BioMate integrates a 15-module cryo-EM single-particle analysis (SPA) pipeline, a 5-module cryo-electron tomography (cryo-ET) pipeline, AlphaFold3 structure prediction, DiffDock and AutoDock Vina molecular docking, MolProbity and EMRinger atomic model quality scoring, and phase plate voltage phase contrast support — all deployable on local GPU workstations, multi-GPU SLURM clusters, or AWS g6.2xlarge cloud instances. The platform is accessible through a conversational AI interface that generates and executes Nextflow workflows in response to natural-language research questions such as: *"Process my 4,200 micrographs collected at 300 kV with a K3 camera, determine preferred orientation using 3DFSC criteria, and automatically flag any junk-dominated 2D classes before refinement."*

---

## 2. Coverage by Cryo-EM/ET Project Phase

The table below maps each standard cryo-EM/ET project phase to BioMate's specific capabilities. Audience notation: **SPA** = single-particle analysis specialist, **ET** = cryo-ET / tomography specialist, **Both** = relevant to both.

| # | Phase | BioMate Capability | Specific Workflows / Tools | Audience | Output |
|---|---|---|---|---|---|
| 1 | **Data Collection QA** | Movie stack import; early-exit validation on corrupted or incompatible files; on-the-fly CTF and motion pre-screening | `IMPORT_MOVIES`, `MOTION_CORRECTION` (pre-screening mode), `CTF_ESTIMATION` (pre-screening mode); QC gate: motion drift GOLD < 50 Å; CTF fit quality GOLD ≥ 0.7 | Both | Validated movie stack manifest; motion-ranked micrograph list; CTF-ranked micrograph list; early failure report for corrupted acquisitions |
| 2 | **Motion Correction** | MotionCor2 (GPU-accelerated) full-frame and patch-based motion correction; dose-weighting | `MOTION_CORRECTION` — MotionCor2; RELION MotionCorr (opensource profile); total drift GOLD gate; per-frame drift advisory; generates dose-weighted and unweighted averages | SPA | Corrected micrograph stacks; motion trajectory plots; drift statistics per-micrograph; QC report (pass / advisory / fail) |
| 3 | **CTF Estimation** | CTFFIND4 and gCTF CTF parameter estimation; phase plate (VPP) CTF support; ice thickness assessment | `CTF_ESTIMATION` — CTFFIND4 (default) / gCTF; fit quality GOLD gate; astigmatism BRONZE advisory; ice thickness BRONZE advisory (ctf_diagnostics.json); VPP phase shift advisory (0.2–1.5 rad range); near-threshold warnings at 0.20–0.22 rad (approaching depletion) and 1.35–1.50 rad (approaching over-charge) | SPA | Per-micrograph CTF parameters (defocus, astigmatism, fit quality, phase shift for VPP); power spectrum thumbnails; ice thickness report; QC summary table |
| 4 | **Micrograph Curation** | Automated acceptance/rejection of micrographs based on combined CTF + motion QC scores | `MICROGRAPH_CURATION` — threshold-based multi-parameter filter; summary histogram of accepted vs. rejected micrographs | SPA | Curated micrograph subset (passing both CTF and motion gates); rejection audit log with per-micrograph reason codes |
| 5 | **Particle Picking** | Neural-network (Topaz), template-based (crYOLO), and blob-based picking; automated particle count advisory | `PARTICLE_PICKING` — Topaz (deep learning picker), crYOLO, LoG blob-based; particle count advisory; box-size sanity check | SPA | Particle coordinate sets; picking summary (counts per micrograph); FPR/TPR estimates for Topaz |
| 6 | **Particle Extraction** | Configurable box size; on-the-fly normalization and contrast inversion | `PARTICLE_EXTRACTION` — CryoSPARC extract / RELION particle extraction (opensource); configurable box size; Fourier cropping for fast 2D | SPA | Extracted particle stacks (MRC/MRCS); particle metadata (coordinates, defocus, phase shift) |
| 7 | **2D Classification** | 2D class averaging; junk fraction QC gate; automatic class quality assessment | `CLASSIFY_2D` — CryoSPARC 2D (default) / RELION 2D (opensource); junk fraction GOLD gate (blocking > 70%); SILVER advisory (50–70%); near-threshold warnings (approaching 50%); automatic feature assignment per class | SPA | 2D class averages; per-class particle counts; junk fraction report; QC gate pass/advisory/fail with class thumbnails |
| 8 | **2D Class Selection** | Automated and interactive class selection; minimum particle count enforcement | `CLASS_SELECTION` — automated threshold-based; manual override supported; exports selected particle stack for ab initio | SPA | Selected particle subset; selection summary; particle count after selection |
| 9 | **Ab Initio Reconstruction** | Stochastic gradient descent (SGD) 3D volume initialization; multi-class ab initio for heterogeneous samples | `AB_INITIO` — CryoSPARC ab initio (default) / RELION 3D classification for initial model (opensource); 1–4 classes configurable | SPA | Initial 3D volume(s); FSC at low resolution; class population fractions |
| 10 | **Homogeneous Refinement** | Gold-standard FSC-regularized single-class refinement; orientation anisotropy QC gate | `HOMOGENEOUS_REFINEMENT` — CryoSPARC homogeneous / RELION 3D auto-refine (opensource); orientation anisotropy ratio GOLD gate (blocking > 10×); SILVER advisory (> 5×); 3DFSC-style anisotropy report | SPA | Refined map at current resolution; FSC curve; per-angle orientation distribution; anisotropy ratio; half-map pair for FSC validation |
| 11 | **Heterogeneous Refinement** | Multi-class 3D classification; conformational state separation | `HETEROGENEOUS_REFINEMENT` — CryoSPARC heterogeneous / RELION multi-body / 3D classification; class population tracking; resolution-per-class estimate | SPA | Per-class 3D maps; FSC per class; particle assignments; conformational trajectory (if cryoDRGN continuous heterogeneity is enabled) |
| 12 | **Non-Uniform Refinement** | CryoSPARC non-uniform regularization for improved map quality in flexible regions | `NON_UNIFORM_REFINEMENT` — CryoSPARC NU-Refine; adaptive regularization; Ewald sphere correction option | SPA | High-resolution NU-refined map; resolution improvement report vs. homogeneous refinement |
| 13 | **CTF Refinement** | Per-particle CTF parameter refinement; beam tilt estimation; higher-order aberration correction | `CTF_REFINEMENT` — CryoSPARC per-particle CTF / RELION CTF refinement (opensource); beam tilt estimation; grouped particle CTF polishing | SPA | Per-particle refined CTF parameters; beam tilt map; resolution improvement estimate |
| 14 | **Map Sharpening & Post-processing** | B-factor sharpening; local resolution-based filtering; density modification | `SHARPENING` — CryoSPARC DeepEMhancer / RELION post-processing (opensource); B-factor advisory gate (> 0 Å² or < −300 Å²); local resolution spread advisory (σ > 3.0 Å); DeepEMhancer density modification | SPA | Sharpened map (MRC); local resolution map; B-factor report; resolution summary (FSC0.143 = X Å) |
| 15 | **AlphaFold3 Structure Prediction** | AI-based atomic model prediction; used as rigid-body docking template into EM map | `ALPHAFOLD3_STRUCTURE_PREDICTION` — AlphaFold3 server API; pTM confidence score; PAE matrix; multi-chain complex prediction | Both | Predicted atomic model (CIF/PDB); pTM/ipTM scores; per-residue pLDDT; PAE matrix heatmap |
| 16 | **Atomic Model Fitting** | Rigid-body fitting of AlphaFold3 / deposited PDB model into EM map; Phenix real-space refinement | Map fitting via RELION / Phenix real_space_refine (opensource profile); RMSD before/after refinement; cross-correlation coefficient (CCC) report | SPA | Fitted atomic coordinates; CCC score; B-factor distribution after refinement |
| 17 | **Atomic Model Quality** | MolProbity Ramachandran and rotamer validation; EMRinger map-model cross-validation | `MOLPROBITY` — MolProbity suite; `EMRINGER` — EMRinger (Barad et al. 2015); all 4 quality gates advisory [BRONZE]; Ramachandran outliers > 2%; rotamer outliers > 5%; clashscore > 20; EMRinger score < 1.0 | SPA | Per-residue Ramachandran plot; Cβ deviation report; clashscore summary; EMRinger score vs. FSC resolution |
| 18 | **Tilt-Series Import (Cryo-ET)** | MDOC-based tilt series alignment; dose-weighting; defect map correction | `IMPORT_TILTSERIES` — Warp / AreTomo2 import; MDOC metadata parsing; tilt angle QC | ET | Tilt series stacks; MDOC metadata tables; per-tilt dose estimate |
| 19 | **Tilt Alignment (Cryo-ET)** | Fiducial-less and fiducial-based tilt series alignment | `TILT_ALIGNMENT` — AreTomo2 (GPU, fiducial-less); IMOD (fiducial-based, opensource); alignment residual report | ET | Aligned tilt series; alignment residual per projection; transformation matrix |
| 20 | **Tomogram Reconstruction (Cryo-ET)** | Weighted back-projection (WBP) and SIRT tomogram reconstruction; deconvolution | `TOMOGRAM_RECONSTRUCTION` — IMOD WBP / SIRT; AreTomo2 reconstruction; all tilt series processed simultaneously (4× throughput vs. IMOD serial) | ET | Tomograms (MRC); deconvolved tomograms; contrast estimate |
| 21 | **Subtomogram Averaging (STA)** | Particle extraction from tomograms; template matching; STA refinement | `SUBTOMOGRAM_AVERAGING` — RELION STA (RELION 4+); Dynamo (optional); symmetry-expanded averaging; FSC per STA round | ET | STA map; FSC; particle coordinates (star file); alignment statistics |
| 22 | **Molecular Docking (Structure-Based)** | Blind and site-directed docking of small molecules into solved EM map | `DIFFDOCK_BLIND_DOCKING` — DiffDock (diffusion-based, highest accuracy); `AUTODOCK_VINA_DOCKING` — AutoDock Vina (grid-based, widely cited); compound SMILES QC gates enforced before docking | SPA + Drug | Binding pose ensemble (SDF/PDB); docking scores (kcal/mol); pose confidence scores; SMILES QC report |

---

## 3. Single-Particle Analysis (SPA) Pipeline — Full Technical View

### What BioMate Offers an SPA Practitioner

An SPA project today involves hundreds to thousands of decisions: which micrographs to include, how many 2D classes to select, what resolution to stop refinement, when to split into heterogeneous classes. BioMate codifies the community's collective wisdom into evidence-graded QC gates that catch data quality problems at each stage — before they cost GPU-hours or obscure real biology. The complete pipeline runs as a single Nextflow workflow with four levels of parallelism: intra-stage batch processing of micrograph groups, inter-stage parallel branches for independent downstream steps, optional GPU multi-worker allocation per CryoSPARC job, and concurrent multi-class ab initio / heterogeneous refinement.

#### Module-by-Module Pipeline

The `spa_full_pipeline/main.nf` orchestrates all 15 SPA modules in sequence with configurable parallelism. Key parameters available at the command line or via the BioMate AI interface:

| Parameter | Description | Default |
|---|---|---|
| `--input_dir` | Directory of raw movie stacks (MRC/TIFF/EER) | required |
| `--pixel_size` | Pixel size in Å/pixel | required |
| `--voltage` | Accelerating voltage (kV): 200 or 300 | 300 |
| `--cs` | Spherical aberration (mm) | 2.7 |
| `--amplitude_contrast` | Amplitude contrast ratio | 0.1 |
| `--phase_plate` | Enable VPP phase plate CTF mode | false |
| `--picker` | Particle picker: `topaz`, `cryolo`, or `blob` | `topaz` |
| `--box_size` | Particle box size in pixels | 256 |
| `--ab_initio_classes` | Number of ab initio 3D classes | 1 |
| `--heterogeneous_classes` | Number of classes for heterogeneous refinement | 2 |
| `--qc_profile` | Named QC profile (see Section 5) | `cryoem_spa_standard` |
| `--outdir` | Output directory | `./results` |

#### CryoSPARC vs. Open-Source Profile

BioMate supports two parallel execution tracks for every SPA stage:

**Default (CryoSPARC):** Uses the CryoSPARC API via `cryosparc-tools` Python client. CryoSPARC's GPU-accelerated algorithms (NU-Refine, per-particle CTF, 2D classification) deliver best-in-class speed and resolution for routine SPA projects. Requires a CryoSPARC license (free for academic use).

**`--profile opensource`:** Maps each process to a specific open-source container — no CryoSPARC license required. Designed for institutions without a CryoSPARC site license, or for fully open reproducible benchmarking:

| SPA Stage | CryoSPARC Tool | Open-Source Replacement |
|---|---|---|
| Motion correction | MotionCor2 | RELION MotionCorr |
| CTF estimation | CTFFIND4 (default for both) | CTFFIND4 |
| Particle picking | CryoSPARC Topaz wrapper | Topaz standalone (PyTorch) |
| 2D classification | CryoSPARC 2D | RELION 2D |
| Ab initio | CryoSPARC SGD ab initio | RELION 3D classification |
| Homogeneous refinement | CryoSPARC homogeneous | RELION 3D auto-refine |
| Heterogeneous refinement | CryoSPARC heterogeneous | RELION 3D classification |
| CTF refinement | CryoSPARC per-particle CTF | RELION CTF refinement |
| Post-processing | DeepEMhancer | RELION post-processing |
| Model fitting | Phenix real_space_refine | Phenix real_space_refine |

#### QC Gates at Each SPA Stage

| Stage | Gate | Level | Threshold | Action on Failure |
|---|---|---|---|---|
| Motion correction | Total motion drift | GOLD | < 50 Å | Block: micrograph rejected from dataset |
| Motion correction | Per-frame drift | BRONZE advisory | < 3 Å/frame | Warning: flagged in QC report, not blocked |
| Motion correction | Approaching drift limit (40–50 Å) | Advisory warning | 40–50 Å | SSE `qc_warning` event |
| CTF estimation | CTF fit quality (Thon ring correlation) | GOLD | ≥ 0.7 | Block: micrograph rejected from dataset |
| CTF estimation | Astigmatism | BRONZE advisory | < 1000 Å | Warning: flagged, not blocked |
| CTF estimation | Ice thickness (thick fraction) | BRONZE advisory | < 50% thick | Warning: from ctf_diagnostics.json |
| CTF phase plate | VPP phase shift (depleted) | SILVER advisory | ≥ 0.2 rad | Warning: plate likely depleted |
| CTF phase plate | VPP phase shift (over-charged) | SILVER advisory | ≤ 1.5 rad | Warning: plate likely over-charged |
| CTF phase plate | Near-threshold (depletion) | Advisory warning | 0.20–0.22 rad | SSE `qc_warning` event |
| CTF phase plate | Near-threshold (over-charge) | Advisory warning | 1.35–1.50 rad | SSE `qc_warning` event |
| 2D classification | Junk fraction | GOLD | < 70% junk classes | Block: run halted; re-pick required |
| 2D classification | Junk fraction advisory | SILVER advisory | < 50% junk | Warning: suggests re-examination of picking parameters |
| 2D classification | Approaching junk limit (45–50%) | Advisory warning | 45–50% | SSE `qc_warning` event |
| Homogeneous refinement | Orientation anisotropy ratio | GOLD | < 10× (best:worst view) | Block: preferred orientation problem; must address detergent/grid conditions |
| Homogeneous refinement | Orientation anisotropy advisory | SILVER advisory | < 5× | Warning: consider 3DFSC validation |
| Sharpening | B-factor range | BRONZE advisory | −300 to 0 Å² | Warning: over-sharpened (> 0) or over-blurred (< −300) |
| Sharpening | Local resolution spread | BRONZE advisory | σ ≤ 3.0 Å | Warning: large spread may indicate multi-conformation averaging |
| Atomic model quality | Ramachandran outliers | BRONZE advisory | ≤ 2% | MolProbity advisory |
| Atomic model quality | Rotamer outliers | BRONZE advisory | ≤ 5% | MolProbity advisory |
| Atomic model quality | Clashscore | BRONZE advisory | ≤ 20 | MolProbity advisory |
| Atomic model quality | EMRinger score | BRONZE advisory | ≥ 1.0 | Barad et al. 2015, Nat Methods — map-model agreement at near-atomic resolution |

#### Voltage Phase Plate (VPP) Support

BioMate provides complete phase plate support for datasets collected with a Volta Phase Plate or similar VPP device:
- Named profile: `cryoem_spa_phase_plate` — relaxes CTF fit quality threshold to 0.65 (VPP datasets legitimately have lower Thon ring contrast)
- Phase shift estimation from `ctf_report.json` emitted by CTFFIND4 VPP mode
- Advisory gates catch both plate depletion (< 0.2 rad, phase contrast lost) and over-charging (> 1.5 rad, phase wraparound)
- Near-threshold warnings at 0.20–0.22 rad and 1.35–1.50 rad allow proactive plate re-conditioning before data quality degrades

#### Representative Nextflow Command — SPA Researcher

```bash
# Standard SPA run from raw EER stacks, 300 kV Titan Krios / K3,
# using the standard named QC profile, Topaz picker, on a SLURM GPU cluster.
nextflow run /path/to/biomate/backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_em/spa_full_pipeline/main.nf \
  -profile slurm \
  --input_dir /data/krios1/20260301_apoferritin/ \
  --pixel_size 0.83 \
  --voltage 300 \
  --cs 2.7 \
  --picker topaz \
  --ab_initio_classes 1 \
  --heterogeneous_classes 3 \
  --qc_profile cryoem_spa_standard \
  --outdir /results/apoferritin_20260301/ \
  -resume

# Phase plate dataset (200 kV Glacios + Volta Phase Plate)
nextflow run .../spa_full_pipeline/main.nf \
  -profile docker \
  --input_dir /data/glacios/20260301_membrane_complex/ \
  --pixel_size 1.00 \
  --voltage 200 \
  --cs 2.7 \
  --phase_plate true \
  --qc_profile cryoem_spa_phase_plate \
  --outdir /results/membrane_complex_vpp_20260301/ \
  -resume

# Open-source profile (no CryoSPARC license) on local workstation
nextflow run .../spa_full_pipeline/main.nf \
  -profile opensource,local_gpu \
  --input_dir /data/benchmark/EMPIAR-10061/ \
  --pixel_size 1.06 \
  --voltage 300 \
  --cs 2.0 \
  --qc_profile cryoem_spa_lowdose \
  --outdir /results/empiar_10061_opensource/ \
  -resume
```

The BioMate AI assistant generates these commands automatically from natural-language input such as: *"Process my apoferritin dataset collected on the Krios at 300 kV with pixel size 0.83 Å, split into 3 conformational classes, and stop me if I have a preferred orientation problem."*

---

## 4. Cryo-Electron Tomography (Cryo-ET) Pipeline — Full Technical View

### What BioMate Offers a Cryo-ET / Structural Cell Biology Researcher

Cryo-ET is uniquely suited to visualize macromolecular complexes in their native cellular environment — but the data processing pipeline is substantially more complex than SPA, and the software landscape is highly fragmented (IMOD, AreTomo2, RELION 4 STA, Dynamo). BioMate provides an integrated, parallelized Nextflow pipeline that processes all tilt series simultaneously — achieving approximately 4× the throughput of IMOD's serial processing model — while maintaining the same evidence-graded QC standards as the SPA pipeline.

#### Cryo-ET Pipeline Modules

**`IMPORT_TILTSERIES`** — Imports raw tilt series stacks with MDOC metadata parsing:
- Reads Thermo Scientific MDOC files for per-tilt dose, stage position, and defocus target
- Validates file integrity before alignment
- Extracts per-tilt dose estimates for dose-weighting
- Supported formats: MRC, MRCS, HDF5 (MotionCor2 output)

**`TILT_ALIGNMENT`** — Aligns tilt series to a common axis:
- Default: **AreTomo2** — GPU-accelerated, fiducial-less alignment using local patch tracking; handles thick samples and samples with limited fiducials well
- Opensource: **IMOD** — gold fiducial-based alignment; classical, widely validated for thin samples and fiducial-labeled specimens
- Outputs: per-tilt transformation matrices; alignment residual statistics; batch statistics across all tilt series (parallel)

**`TOMOGRAM_RECONSTRUCTION`** — Generates 3D tomogram volumes:
- Methods: weighted back-projection (WBP; fast, standard), SIRT (iterative, better contrast for thick samples), dose-weighted WBP
- All tilt series in the dataset are reconstructed simultaneously (Nextflow parallelism — each tilt series is an independent process)
- Deconvolution filter (Wiener-based) option for improved feature visibility
- Benchmark: 3 tomograms processed in parallel validate correctly at 20 IMOD-equivalent sequential steps

**`SUBTOMOGRAM_AVERAGING`** — Extracts and averages particles from tomograms:
- Template matching for initial particle picking from tomograms
- RELION 4 STA pipeline for alignment and iterative averaging
- Symmetry expansion support
- Gold-standard FSC per STA round
- Optional Dynamo integration for custom sub-volume analysis

**`ET_FULL_PIPELINE`** — Runs all four modules end-to-end with intra-stage parallelism:
- All tilt series processed simultaneously in `TILT_ALIGNMENT` and `TOMOGRAM_RECONSTRUCTION`
- STA runs on the merged particle set from all reconstructed tomograms
- Resume support: interrupted runs restart from last completed tilt series

#### Representative Nextflow Command — Cryo-ET Researcher

```bash
# Cryo-ET pipeline: MDOC tilt series, AreTomo2 alignment, WBP reconstruction,
# RELION 4 STA, on a multi-GPU SLURM cluster.
nextflow run /path/to/biomate/backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_et/et_full_pipeline/main.nf \
  -profile slurm \
  --input_dir /data/et_session/20260301_ribosomes/ \
  --pixel_size 1.8 \
  --voltage 300 \
  --tilt_range "-60,60" \
  --tilt_step 3 \
  --alignment_method aretomo2 \
  --reconstruction_method wbp \
  --sta_symmetry C1 \
  --outdir /results/ribosomes_et_20260301/ \
  -resume
```

The BioMate AI assistant translates natural-language requests: *"Run tilt series alignment and subtomogram averaging on my in-situ ribosome dataset, use AreTomo2 for alignment, and give me a final STA map with FSC validation."*

---

## 5. Structure Prediction and Structure-Based Drug Design

### AlphaFold3 Structure Prediction

BioMate integrates the **AlphaFold3 server API** for structure prediction of proteins, nucleic acids, and multi-chain complexes — directly feeding predicted models into the SPA model-fitting and docking workflows:

- Input: protein sequence (FASTA), ligand SMILES (optional), RNA/DNA cofactor sequences
- Generates: all-atom predicted structure (CIF format); pTM, ipTM confidence scores; PAE (predicted aligned error) matrix; per-residue pLDDT
- Use cases:
  - Generate a starting model for rigid-body docking into an EM map when no crystal structure exists
  - Predict the structure of binding partners before pull-down or cross-linking MS experiments
  - Identify flexible regions (low pLDDT, high PAE) before cryo-EM data collection to inform sample prep strategy
- Integrated pipeline: `ALPHAFOLD3_STRUCTURE_PREDICTION → HOMOGENEOUS_REFINEMENT` (model-guided refinement) or `ALPHAFOLD3_STRUCTURE_PREDICTION → DIFFDOCK_BLIND_DOCKING` (structure-based virtual screening)

### Molecular Docking — Three Approaches

Once a cryo-EM structure is solved, BioMate provides three docking methods at different speed/accuracy trade-offs:

**`DIFFDOCK_BLIND_DOCKING`** — Diffusion-based molecular docking (DiffDock, CorsoPaper et al. 2022):
- Blind docking: no box required; samples the full protein surface
- Generates an ensemble of 10 binding poses ranked by confidence score
- Best accuracy for flexible binding sites and novel binding modes
- Container: `simonelenz/diffdock:latest`
- Input: protein PDB (from cryo-EM refinement or AlphaFold3) + compound SMILES

**`AUTODOCK_VINA_DOCKING`** — Grid-based molecular docking:
- Classical, widely cited, reproducible reference method
- Requires binding site box specification (uses `run_autosite` output or user-defined coordinates)
- Fast execution for large compound libraries (virtual screening mode)
- Container: `cford38/autodockvina:latest`
- Generates 9 docking modes per compound with binding affinity in kcal/mol

**Structure-to-screening pipeline (`structure_prediction_docking/main.nf`):**
- Stage 1: AlphaFold3 structure prediction (or import from cryo-EM refinement)
- Stage 2: Binding site prediction via `run_autosite`
- Stage 3: DiffDock and AutoDock Vina run in parallel on the same compound library
- SMILES QC gates enforced before any docking compute is consumed (GOLD: RDKit validity; SILVER: salt stripping, undefined stereocenters; BRONZE: molecular weight)
- Comparison report: DiffDock pose confidence vs. Vina affinity for consensus ranking

### Atomic Model Quality Scoring

After model fitting into an EM map, BioMate runs two complementary model quality assessment tools:

**`MOLPROBITY`** — All-atom stereochemistry validation:
- Ramachandran outlier fraction: advisory BRONZE gate if > 2% (Lovell et al. 2003, Proteins 50:437-450)
- Rotamer outlier fraction: advisory BRONZE gate if > 5% (MolProbity 4.0)
- All-atom clashscore: advisory BRONZE gate if > 20
- Cβ deviations, omega angle outliers, non-rotameric side-chain statistics
- Output: residue-level annotation; PDB with B-factor replaced by clash score

**`EMRINGER`** — Map-model cross-validation at the backbone/side-chain level:
- EMRinger score: advisory BRONZE gate if < 1.0 (Barad et al. 2015, Nature Methods 12:943-946)
- Validates side-chain dihedral angle peaks against local electron density (independent of model-building tool used)
- Particularly sensitive to model errors in near-atomic resolution (2.5–4.5 Å) maps where model-building is error-prone

---

## 6. QC Governance Summary

BioMate applies a three-tier evidence-graded QC system across all cryo-EM and structural biology stages. Evidence levels follow the governance framework defined in the BioMate QC paper (Paper 1):

- **GOLD**: Universally accepted threshold with multiple independent validations; failure blocks workflow execution
- **SILVER**: Strong evidence from domain-specific standards or major guidelines; failure blocks workflow execution (advisory variant is non-blocking)
- **BRONZE**: Community heuristic or single-source evidence; advisory only (never blocks)

When a QC gate passes but a metric is approaching a threshold (within 5–10% of the threshold value), BioMate emits a `qc_warning` SSE event to the frontend — giving researchers early notice of potential problems before they compound over downstream GPU-expensive stages.

### Complete QC Gate Table — Cryo-EM Domain

| Domain | Stage | Metric | Level | Threshold | Citation |
|---|---|---|---|---|---|
| **Cryo-EM SPA** | Motion correction | Total motion drift | GOLD blocking | < 50 Å | CryoSPARC documentation; MotionCor2 best practices (Zheng et al. 2017, Nat Methods) |
| **Cryo-EM SPA** | Motion correction | Per-frame drift | BRONZE advisory | < 3 Å/frame | Community heuristic |
| **Cryo-EM SPA** | Motion correction | Approaching drift limit | Warning | 40–50 Å | Near-threshold detection |
| **Cryo-EM SPA** | CTF estimation | CTF fit quality (Thon ring correlation) | GOLD blocking | ≥ 0.7 | Rohou & Grigorieff 2015, JSB 192:216-221 (CTFFIND4) |
| **Cryo-EM SPA** | CTF estimation | Astigmatism | BRONZE advisory | < 1000 Å | No published consensus threshold; fit quality is primary gate |
| **Cryo-EM SPA** | CTF estimation | Ice thickness (thick fraction) | BRONZE advisory | < 50% thick | ctf_diagnostics.json heuristic; Rice et al. 2018, PNAS |
| **Cryo-EM SPA** | CTF phase plate (VPP) | Phase shift — depleted | SILVER advisory | ≥ 0.2 rad | Danev et al. 2014, PNAS; phase plate manufacturer guidelines |
| **Cryo-EM SPA** | CTF phase plate (VPP) | Phase shift — over-charged | SILVER advisory | ≤ 1.5 rad | ibid. |
| **Cryo-EM SPA** | CTF phase plate (VPP) | Near depletion threshold | Advisory warning | 0.20–0.22 rad | Near-threshold detection |
| **Cryo-EM SPA** | CTF phase plate (VPP) | Near over-charge threshold | Advisory warning | 1.35–1.50 rad | Near-threshold detection |
| **Cryo-EM SPA** | 2D classification | Junk class fraction | GOLD blocking | < 70% junk | CryoSPARC SPA best practices; Punjani et al. 2017, Nat Methods |
| **Cryo-EM SPA** | 2D classification | Junk fraction advisory | SILVER advisory | < 50% junk | CryoSPARC SPA recommendations |
| **Cryo-EM SPA** | 2D classification | Approaching junk limit | Warning | 45–50% | Near-threshold detection |
| **Cryo-EM SPA** | Homogeneous refinement | Orientation anisotropy ratio (best:worst) | GOLD blocking | < 10× | Tan et al. 2017, Nat Methods 14:793-796 (3DFSC) |
| **Cryo-EM SPA** | Homogeneous refinement | Orientation anisotropy advisory | SILVER advisory | < 5× | ibid. |
| **Cryo-EM SPA** | Sharpening | B-factor range | BRONZE advisory | −300 to 0 Å² | Rosenthal & Henderson 2003, JMB 333:721-745; typical map range −100 to −250 Å² |
| **Cryo-EM SPA** | Local resolution | Spread (σ) across map | BRONZE advisory | σ ≤ 3.0 Å | CryoSPARC local resolution documentation |
| **Atomic model quality** | MolProbity | Ramachandran outlier fraction | BRONZE advisory | ≤ 2% | Lovell et al. 2003, Proteins 50:437-450; MolProbity 4.0 |
| **Atomic model quality** | MolProbity | Rotamer outlier fraction | BRONZE advisory | ≤ 5% | MolProbity 4.0; Williams et al. 2018, Protein Sci 27:293-315 |
| **Atomic model quality** | MolProbity | All-atom clashscore | BRONZE advisory | ≤ 20 | MolProbity 4.0 |
| **Atomic model quality** | EMRinger | EMRinger score | BRONZE advisory | ≥ 1.0 | Barad et al. 2015, Nat Methods 12:943-946 |
| **Compound / SMILES** | SMILES validation | RDKit SMILES validity | GOLD blocking | 0 invalid SMILES | Whitehead et al. 2022, J Chem Inf Model (15% error rate in deposited SMILES) |
| **Compound / SMILES** | SMILES validation | Salt stripping | SILVER advisory | Auto-stripped, transform logged | RDKit MolStandardize best practice |
| **Compound / SMILES** | SMILES validation | Undefined stereocenters | SILVER advisory | 0 undefined | Cheminformatics best practice |

### Named QC Profiles — Cryo-EM

BioMate ships three named QC profiles for cryo-EM SPA, each pre-configured for a common experimental scenario. Profiles are selected via `--qc_profile` at the command line or through the BioMate AI interface.

| Profile Name | Use Case | Key Adjustments vs. Default |
|---|---|---|
| `cryoem_spa_standard` | Standard SPA at 300 kV (Titan Krios / K3 / Falcon) | All default thresholds as described above |
| `cryoem_spa_lowdose` | Low-dose cryo-EM (< 40 e⁻/Å²); EMPIAR benchmark mode | CTF fit quality relaxed to 0.65 (lower SNR at low dose); motion drift gate relaxed to 60 Å (more motion acceptable at low dose) |
| `cryoem_spa_phase_plate` | Volta Phase Plate (VPP) datasets | CTF fit quality relaxed to 0.65 (VPP Thon rings have lower contrast); phase shift gate activated (0.2–1.5 rad advisory); astigmatism advisory threshold unchanged |

All three profiles inherit the full QC gate set; they only adjust the numeric thresholds for gates where experimental conditions legitimately produce different expected values. All threshold adjustments are audited — overrides are logged to `work_dir/qc_overrides_audit.jsonl` per invocation.

---

## 7. EMPIAR Benchmark Datasets

BioMate's cryo-EM pipeline has been validated against publicly available EMPIAR datasets. These same datasets are used as benchmarks for Paper B (cryo-EM benchmark paper):

| Dataset | Target | Resolution (reported) | Voltage | Pixel Size | Notes |
|---|---|---|---|---|---|
| EMPIAR-10061 | TRPV1 channel | 3.8 Å | 300 kV | 1.2165 Å/px | Reference SPA benchmark; Liao et al. 2013, Nature 504:107-112 |
| EMPIAR-10028 | Apoferritin (HEK293) | 2.8 Å | 300 kV | 1.0 Å/px | Near-atomic resolution test; Zivanov et al. 2018, eLife |
| EMPIAR-10248 | HIV-1 CA-SP1 | 3.9 Å | 300 kV | 0.637 Å/px | Preferred orientation test case (anisotropy gate validation) |
| EMPIAR-10164 | Actin-tropomyosin | 3.7 Å | 300 kV | 1.31 Å/px | Helical SPA variant; used for pipeline generalization testing |

The `cryoem_spa_lowdose` profile is calibrated specifically for low-dose EMPIAR benchmarking runs (< 40 e⁻/Å²) where the default CTF and motion thresholds are too stringent for the intentionally low-SNR test conditions.

---

## 8. Technology Stack

### Workflow Execution Engine

**Nextflow DSL2 (nf-core standard)** — All BioMate cryo-EM pipelines follow nf-core module conventions: each module is an independent, versioned, containerized process with `meta` channel semantics. Pipelines are composed from modules using nf-core subworkflow patterns. Workflow state is checkpointed; interrupted runs resume from the last completed stage (`-resume` flag).

### Container Strategy

- **Docker** — default for local GPU workstations and cloud instances; all modules have Docker container specifications
- **Singularity** — supported via `-profile singularity`; required for HPC/SLURM environments without Docker daemon (standard at national cryo-EM facilities)
- **Open-source profile** — maps every SPA process to a specific versioned open-source container (RELION 3.1, CTFFIND4, Topaz, Phenix) without any CryoSPARC container; full pipeline runs with zero proprietary software

### GPU Compute Requirements

| Workload | Minimum GPU | Recommended | AWS Instance |
|---|---|---|---|
| SPA (CryoSPARC, standard dataset) | 24 GB VRAM (e.g. RTX 3090) | A100 40 GB | g6.2xlarge (L40S, 48 GB) |
| SPA (RELION open-source, Krios-scale) | 16 GB VRAM | 2× A100 | g6.12xlarge |
| Cryo-ET reconstruction (AreTomo2) | 12 GB VRAM | 24 GB | g4dn.xlarge |
| AlphaFold3 structure prediction | Server API (no local GPU) | — | — |
| DiffDock docking | 8 GB VRAM | 16 GB | g4dn.xlarge |
| AutoDock Vina docking | CPU-only | 8-core CPU | c6i.4xlarge |

**Minimum for CryoSPARC v5:** 32 GB RAM; CryoSPARC v5 SPA jobs have been confirmed to use 24 GB RAM. Academic CryoSPARC license: free (cryosparc.com/download).

### Compute Backends

| Backend | Configuration | Use Case |
|---|---|---|
| Local GPU workstation | `executor = 'local'` (default), `-profile local_gpu` | Small datasets; development; single-user facility |
| Multi-GPU local cluster | `-profile multi_gpu` | Large-scale SPA (> 10,000 micrographs) |
| SLURM GPU partition | `executor = 'slurm'`, `-profile slurm` | National cryo-EM facilities; institutional HPC |
| AWS Batch + GPU | `executor = 'awsbatch'`, `-profile aws` | Cloud-burst for peak demand; benchmark runs |
| Singularity on HPC | `-profile singularity,slurm` | Facilities without Docker; NERSC, TACC, XSEDE resources |

Per-invocation compute configuration overrides are supported from the BioMate settings UI (`Compute` tab): executor type, SLURM queue name, GPU count per job, AWS S3 bucket, and local output directory can be set globally or overridden per workflow invocation.

### BioMate AI Assistant Layer

The BioMate frontend provides a conversational AI interface (Claude Sonnet / Anthropic API) that:
- Interprets natural-language research questions and maps them to specific Nextflow workflow invocations
- Generates `workflow_artifact` objects with pre-filled parameters, QC profile selection, and compute configuration
- Streams workflow progress, QC gate events, and per-stage intermediate results to the UI via Server-Sent Events (SSE)
- Enforces QC gate decisions through the QC gate modal (block / override with documented justification)
- Tracks per-workflow LLM token costs and compute costs through the billing infrastructure

**Example natural-language queries that BioMate can interpret and execute:**

1. *"I have 3,200 micrographs from the Krios at 0.83 Å/pixel, 300 kV. Run the full SPA pipeline with Topaz picking and split into 4 conformational classes. Alert me if I have preferential orientation."*
2. *"My CTF quality scores are dropping — is this an ice thickness issue or astigmatism? Show me a histogram of fit quality across all micrographs."*
3. *"Run the open-source RELION pipeline on my EMPIAR-10061 download and compare the FSC resolution to the published 3.8 Å."*
4. *"I solved a 3.2 Å map of my target. Predict its structure with AlphaFold3 and dock our top 20 compounds using DiffDock."*
5. *"My Phase Plate dataset looks unusual — show me the phase shift distribution and flag any micrographs where the plate appears depleted."*
6. *"Process my tilt series, reconstruct tomograms, and run subtomogram averaging on the ribosome particles. Use AreTomo2 for alignment."*

### Cryo-EM Data Sources and Integrations

| Source | Integration |
|---|---|
| EMPIAR (EMDB) | Benchmark dataset downloads; BioMate dataset registry (`biomate_dataset_registry.json`) |
| RCSB PDB | Model download for fitting; SMILES retrieval for bound ligands |
| AlphaFold3 server API | Structure prediction from sequence (no local GPU required) |
| CryoSPARC API (cryosparc-tools) | Direct job submission, monitoring, and result retrieval |
| RELION / CTFFIND4 / Topaz | Open-source pipeline containers (no external API) |
| MolProbity server | Atomic model quality scoring (local via Phenix container) |
| EMRinger | Map-model cross-validation (local via Phenix/cctbx container) |

---

## 9. QC Report Export

BioMate generates a structured QC report for each workflow invocation via the `POST /api/export/qc_report` endpoint. The report is available in both JSON and PDF/HTML formats and includes:

- **Per-stage QC results**: metric values, thresholds, gate level (GOLD/SILVER/BRONZE), pass/advisory/fail status
- **Override audit log**: if any QC gate was overridden, the override value, justification, and user are recorded
- **Pipeline parameters**: pixel size, voltage, Cs, picker used, QC profile name and version
- **Compute provenance**: executor, container versions, Nextflow version, run start/end timestamps
- **Summary resolution**: final FSC₀.₁₄₃ resolution, map deposition-ready filename

This report is designed to be attached directly to cryo-EM structure depositions (EMDB/PDB) as the "data processing QC certificate" required by EMDB deposition guidelines.

---

## Appendix: Workflow Location Reference

All workflows are located under `backend/` in the BioMate repository:

| Workflow Category | Path |
|---|---|
| SPA full pipeline (15 modules) | `biomni_workflows/nextflow_nfcore/subworkflows/cryo_em/spa_full_pipeline/main.nf` |
| Individual SPA modules | `biomni_workflows/nextflow_nfcore/subworkflows/cryo_em/*/main.nf` |
| Cryo-ET full pipeline (5 modules) | `biomni_workflows/nextflow_nfcore/subworkflows/cryo_et/et_full_pipeline/main.nf` |
| Individual cryo-ET modules | `biomni_workflows/nextflow_nfcore/subworkflows/cryo_et/*/main.nf` |
| AlphaFold3 + docking pipeline | `biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/structure_prediction_docking/main.nf` |
| QC governance layer | `lib/galaxy/jobs/qc_trace_monitor.py` |
| Nextflow executor | `lib/galaxy/webapps/galaxy/api/nextflow_executor_v2.py` |
| EMPIAR benchmark dataset registry | `biomate_dataset_registry.json` (repository root) |
| QC threshold JSON export | `qc_thresholds.json` (repository root) |
| Open-source tool catalog | `auto_update/data/cryo_em_tool_catalog.json` (20 steps, 76 alternatives) |
| CryoSPARC cloud setup guide | `docs/CRYOSPARC_CLOUD_SETUP_GUIDE.md` |
