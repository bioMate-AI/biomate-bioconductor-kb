# CryoSPARC Standard SPA — Technical Report Generation Protocol

**Date:** 2026-04-27  
**Scope:** BioMate `/api/invocations/:id/methods-report` for `cryosparc_standard_spa` workflow  
**Target:** Journal-submission-quality Methods + Results section (IUCrJ, Nature Methods, eLife, JSB)

---

## 1. Purpose

This protocol defines exactly how a CryoSPARC SPA technical report is generated from pipeline step outputs. It replaces ad-hoc LLM-only generation with a structured data-extraction pass followed by LLM narrative synthesis. Any generated section that lacks the required input data MUST be flagged explicitly ("data not available — re-run required") rather than silently omitted or fabricated.

---

## 2. Required Input Data Sources

The report generation system reads the following files from the pipeline's S3 output directory. Each file is associated with specific required fields.

### 2.1 Phase A — Motion Correction + CTF

| File | Required Fields | Notes |
|------|----------------|-------|
| `02_motion_correction/batch_*/motion_report_batch_*.json` | `num_micrographs`, `avg_total_motion_A`, `min_total_motion_A`, `max_total_motion_A` | Fixed in run9+ |
| `03_ctf_estimation/batch_*/ctf_report_batch_*.json` | `num_micrographs`, `avg_defocus_A`, `avg_fit_quality`, `avg_astigmatism_A` | Fixed in run9+ |
| `04_denoiser/denoise_report.json` | step completion only | Optional |

### 2.2 Phase B — Particle Picking + Extraction

| File | Required Fields |
|------|----------------|
| `05_blob_picker/batch_*/picking_report_batch_*.json` | `num_particles`, `particle_diameter_angstroms` |
| `06_junk_detector/junk_report.json` | `num_input_particles`, `num_output_particles`, `rejection_rate` |
| `07_inspect_picks_round1/inspect_report.json` | `num_particles` |
| `08_extract_round1/batch_*/extract_report_batch_*.json` | `num_particles`, `box_size_pix` |

### 2.3 Phase C — 2D Classification + Selection

| File | Required Fields |
|------|----------------|
| `09_classify_2d_round1/pbatch_*/class2d_report_pbatch_*.json` | `num_particles`, `num_classes`, `cs_job_uid` |
| `10_select_2d_round1/selection_report.json` | `num_input_particles`, `num_selected_particles`, `selection_ratio` |
| `11_template_picker/template_pick_report.json` | `num_particles`, `cs_job_uid` |
| `12_inspect_picks_round2/inspect_report.json` | `num_particles` |
| `13_extract_round2/extract_report.json` | `num_particles`, `box_size_pix` |
| `14_classify_2d_round2/pbatch_*/class2d_report_r2_pbatch_*.json` | `num_particles`, `num_classes` |
| `15_select_2d_round2/selection_report.json` | `num_input_particles`, `num_selected_particles`, `selection_ratio` |

### 2.4 Phase D — Ab-Initio + Homogeneous Refinement

| File | Required Fields |
|------|----------------|
| `16_ab_initio/model_*/ab_initio_report_k*.json` | `num_particles`, `cs_job_uid`, `symmetry` |
| `17_homogeneous_refinement/vol_*/refinement_report_vol_*.json` | `num_particles`, `cs_job_uid`, `symmetry`, `viz_files` |
| `18_volume_tools/volume_tools_report.json` | `cs_job_uid`, `operations` |

### 2.5 Phase E — Post-Processing + Final Map

| File | Required Fields |
|------|----------------|
| `19_validation_fsc/fsc_validation.json` | `fsc_curve` (array of `{spatial_frequency, resolution_angstroms, fsc}`), `fsc_0143_resolution` |
| `20_local_ctf_refinement/ctf_refinement_report.json` | `cs_job_uid`, step completion |
| `21_non_uniform_refinement/nu_refinement_report.json` | `num_particles`, `cs_job_uid`, `viz_files` |
| `22_local_resolution/local_resolution_report.json` | `mean_resolution_angstroms`, `min_resolution_angstroms`, `max_resolution_angstroms` |
| `23_sharpening/sharpening_report.json` | `cs_job_uid`, `final_output`, `viz_files` |
| `23_sharpening/workflow_summary.json` | `steps_completed`, `pixel_size_angstroms`, `voltage_kv`, `symmetry` |

---

## 3. Data Extraction Algorithm

Before calling the LLM, the report engine must:

1. **List all JSON files** in the run's S3 outdir (via `aws s3 ls --recursive`)
2. **Download all `*_report*.json` and `*_summary*.json`** files (max 8 files, 6000 chars each for LLM context)
3. **Parse required fields** for each section (Table 2.1–2.5 above)
4. **Compute aggregate metrics**:
   - Total particles at each processing stage (sum across batches)
   - Overall particle yield: `final_particles / picked_particles × 100%`
   - Motion correction quality: `avg_total_motion_A` (field standard: <10 Å)
   - CTF fit quality score (0–1 scale): `1 - avg_fit_quality_raw / 10`
   - FSC resolution at 0.143: from `fsc_validation.json.fsc_0143_resolution`
5. **Record data availability** for each required field — flag missing as `MISSING`

---

## 4. Report Section Specifications

### Section 1: Abstract (≤150 words)
**Required content:** Sample name/accession; number of micrographs; final particle count; final resolution (FSC 0.143); software (CryoSPARC version); pipeline (BioMate); key quality metrics (motion, CTF)  
**Cannot be generated without:** `workflow_summary.json`, at minimum one `motion_report`, `fsc_0143_resolution`

### Section 2: Study Overview
**Required content:** Biological question; dataset source (EMPIAR accession if available); significance of CryoEM for this target; symmetry applied; pixel size and box size justification  
**Required parameters from run:** `pixel_size_angstroms`, `voltage_kv`, `symmetry`, `particle_diameter_angstroms`

### Section 3: Computational Environment
**Required content:** AWS region (`us-west-2`); instance type (`g6.2xlarge` for GPU phases, `c5n.4xlarge` for CPU); GPU model (NVIDIA L4, 24 GB VRAM); vCPU count (8); RAM (32 GB); CryoSPARC version (`v5.0.2`); cryosparc-tools version; Nextflow version; BioMate pipeline version  
**Source:** `workflow_summary.json`, run parameters, Nextflow trace

### Section 4: Data Acquisition and Preprocessing
**Required content:** Number of micrographs (`num_micrographs`); beam energy (`voltage_kv`); pixel size (`pixel_size_angstroms`); motion correction algorithm (Patch Motion Correction); number of patches; average total motion (Å); defocus range (Å); average CTF fit quality; dose-weighting applied (yes/no)  
**Quality thresholds (field standard):**
- Average total motion: < 10 Å (good: < 5 Å)
- CTF fit quality: > 0.75 (good: > 0.90)
- Defocus range: 0.5–4.0 µm (1,000–40,000 Å)

### Section 5: Methods
One paragraph per processing stage. Required detail per stage:

**5.1 Motion Correction (CryoSPARC Patch Motion Correction)**  
> Patch motion correction was performed using CryoSPARC v5.0.2 Patch Motion Correction (Punjani et al. 2017). N={num_micrographs} micrographs were processed in batches of {batch_size}. Average total drift per micrograph was {avg_total_motion_A} Å (range: {min_total_motion_A}–{max_total_motion_A} Å). Dose-weighting was applied using the total fluence of {dose_per_frame} e⁻/Å² per frame (if available).

**5.2 CTF Estimation (CryoSPARC Patch CTF)**  
> Contrast transfer function parameters were estimated using CryoSPARC Patch CTF (CTFFIND4 algorithm, Rohou & Grigorieff 2015 as implemented in CryoSPARC). Mean defocus was {avg_defocus_A/10000:.2f} µm. Average CTF fit quality score was {avg_fit_quality:.3f}. Micrographs with fit quality < 0.5 were excluded from further processing.

**5.3 Particle Picking (Blob Picker + Template Picker)**  
> Initial particle candidates were identified by blob picker ({blob_diameter_A} Å particle diameter), yielding {num_blob_particles} candidate locations. After 2D classification (Round 1, {num_classes_r1} classes, {num_particles_r1} particles), high-quality 2D class average templates were used for a second picking pass (template picker, CryoSPARC v5.0.2), yielding {num_template_particles} candidate locations.

**5.4 Particle Extraction**  
> Particles were extracted with a box size of {box_size_pix}² pixels at {pixel_size_angstroms} Å/pixel ({box_size_A:.1f} Å box). Round-1 extraction yielded {num_extracted_r1} particles. After template-based picking, Round-2 extraction yielded {num_extracted_r2} particles.

**5.5 2D Classification (Rounds 1 and 2)**  
> Round-1 2D classification was performed on {num_particles_r1} particles into {num_classes_r1} classes using CryoSPARC. {num_selected_r1} particles ({selection_ratio_r1*100:.1f}%) were selected for downstream analysis. Round-2 2D classification on {num_particles_r2} particles into {num_classes_r2} classes produced {num_selected_r2} selected particles ({selection_ratio_r2*100:.1f}%).

**5.6 Ab-Initio Reconstruction**  
> Ab-initio 3D reconstruction was performed using CryoSPARC ab-initio reconstruction (SGDSGD algorithm) with K={num_ab_initio_classes} initial models to avoid local minima. Symmetry {symmetry} was imposed. {num_particles_abinit} particles were used.

**5.7 Homogeneous Refinement**  
> Each of the K ab-initio volumes was refined using CryoSPARC homogeneous refinement with {num_particles_abinit} particles and symmetry {symmetry}. The refinement with lowest nominal resolution was selected as the input to post-processing (CryoSPARC v5 internal FSC criterion).

**5.8 Post-Processing (CTF Refinement + Non-Uniform Refinement)**  
> Local CTF refinement was performed using CryoSPARC per-particle local defocus estimation (Punjani & Fleet 2021). Non-uniform refinement was performed on {num_particles_nu} particles using CryoSPARC non-uniform refinement (Punjani et al. 2020) with symmetry {symmetry}.

**5.9 FSC Validation + Map Sharpening**  
> Resolution was assessed by gold-standard FSC (two independent half-datasets). The map-sharpening B-factor was estimated using the Rosenthal-Henderson procedure. Local resolution estimation was performed using CryoSPARC local resolution.

### Section 6: Pipeline Execution
**Required content:** Total wall time; per-phase wall times; AWS Batch job count; CryoSPARC project UID; number of CPU and GPU hours (estimated)  
**Source:** `workflow_summary.json.completion_time` - `timing.json.started_at`; Nextflow trace file

### Section 7: Results
**CRITICAL — all numbers must come from actual output files. Never interpolate or estimate.**

Required table format:

| Processing Stage | Particles In | Particles Out | Yield |
|-----------------|-------------|--------------|-------|
| Blob picking | {num_micrographs} mics | {num_blob_particles} | — |
| Junk filtering | {num_blob_particles} | {num_junk_out} | {100-rejection_rate*100:.1f}% |
| Extract R1 | ... | {num_extracted_r1} | ... |
| 2D classify R1 | {num_extracted_r1} | {num_selected_r1} | {selection_ratio_r1*100:.1f}% |
| Template picking | ... | {num_template_particles} | — |
| Extract R2 | ... | {num_extracted_r2} | ... |
| 2D classify R2 | {num_extracted_r2} | {num_selected_r2} | {selection_ratio_r2*100:.1f}% |
| Ab-initio | {num_selected_r2} | {num_particles_abinit} | — |
| Homo refine | {num_particles_abinit} | {num_particles_homo} | — |
| NU refine | {num_particles_homo} | {num_particles_nu} | — |

**Resolution:** FSC 0.143 resolution = {fsc_0143_resolution} Å (or "data not available — VALIDATION_FSC run required")

**Map quality:** mean local resolution range {local_res_min}–{local_res_max} Å (if available)

### Section 8: Scientific Interpretation

**Required content:** Comparison of resolution to field standard for this sample class at this particle count; assessment of particle yield (low/normal/high); motion quality assessment; CTF quality; limitations; recommendations for improvement  

**Quality benchmarks (field standards):**
- Resolution at 10K particles: typically 8–15 Å for well-behaved samples
- Resolution at 100K particles: typically 3–5 Å
- Resolution at 1M particles: potentially sub-3 Å with good sample
- Good motion: total drift < 5 Å; Excellent: < 3 Å
- Good CTF: fit quality > 0.85; Excellent: > 0.95
- Expected particle yield: 15–25% of picked particles reach final refinement

### Section 9 (CryoEM only): Data Quality Assessment
**Required content:**
- Resolution at FSC 0.143 (gold-standard): {fsc_0143_resolution} Å
- FSC 0.5 resolution (conservative criterion): {fsc_05_resolution} Å
- Local resolution range: {local_res_min}–{local_res_max} Å
- Rosenthal-Henderson B-factor: {b_factor} Å² (from sharpening_report if available)
- Sphericity score / preferred orientation (if computed)
- Overall particle yield: {final_particles}/{picked_particles} = {yield_pct}%
- Defocus range: {defocus_min/10000:.2f}–{defocus_max/10000:.2f} µm
- CTF fit quality: {avg_fit_quality:.3f}

### Section 10 (CryoEM only): EMDB Deposition Note + Reproducibility

**Deposition metadata template:**
```
Recommended deposition metadata for EMDB submission:
- Pixel size: {pixel_size_angstroms} Å/voxel
- Symmetry imposed: {symmetry}
- Box size: {box_size_pix}³ pixels ({box_size_A:.1f}³ Å)
- Final particle count: {num_particles_nu}
- Applied B-factor: {b_factor} Å² (negative = sharpening)
- Reconstruction software: CryoSPARC v5.0.2
- Resolution (FSC 0.143): {fsc_0143_resolution} Å
```

**Reproducibility:** Pipeline version, random seed (none — CryoSPARC uses deterministic SGD by default), parameter archive at `{workflow_summary_s3_path}`.

---

## 5. Required Citations

These citations MUST appear in every CryoSPARC SPA report regardless of data availability:

| Tool | Citation | PMID |
|------|---------|------|
| CryoSPARC | Punjani et al. (2017) Nature Methods 14:290–296 | 28165473 |
| Patch CTF (CTFFIND4 algorithm) | Rohou & Grigorieff (2015) JSB 192:216–221 | 26278980 |
| MotionCor2 (patch motion) | Zheng et al. (2017) Nature Methods 14:331–332 | 28250466 |
| Non-uniform refinement | Punjani et al. (2020) Nature Methods 17:1214–1221 | 33257830 |
| Local CTF refinement | Punjani & Fleet (2021) Nature Methods 18:860–869 | 34282325 |
| DeepEMhancer (if map sharpening) | Sanchez-Garcia et al. (2021) Commun Biol 4:874 | 34267316 |

Optional (include if applicable):
| cryoDRGN (heterogeneity) | Zhong et al. (2021) Nature Methods 18:930–936 | 34267337 |
| RELION (if used) | Zivanov et al. (2018) eLife 7:e42166 | 30412051 |

---

## 6. Missing Data Handling

| Missing data | Required text |
|-------------|--------------|
| `fsc_curve: []` or absent | "FSC validation data not available for this run. Resolution assessment requires re-running with VALIDATION_FSC process using the corrected main.nf (fix applied 2026-04-27)." |
| `num_particles: 0` in refinement | "Particle count metadata is unavailable due to a pipeline metadata propagation bug (fixed 2026-04-27). The CryoSPARC API executed correctly — particle counts can be retrieved directly from CryoSPARC project P{project_uid}." |
| `avg_total_motion_A` absent | "Motion correction quality metrics not extracted. Re-run with updated pipeline to obtain drift statistics." |
| `local_resolution_report.json` absent | "Local resolution map not generated (LOCAL_RESOLUTION process may have failed silently; errorStrategy='ignore')." |

---

## 7. Implementation Notes

The report generation in `frontend/server/routes.ts` must:

1. **First pass: structured extraction** — Download all JSON reports, parse them into a structured `CryoSPARCRunData` object with all fields from §2 above. Flag each field as `available | missing`.

2. **Second pass: LLM synthesis** — Pass the `CryoSPARCRunData` struct to Gemini Flash along with the section specs from §4. The LLM fills prose around the numbers; it does NOT invent numbers.

3. **Validation pass** — After LLM generates text, verify all numbers in the report appear in the source data. If a number is fabricated, replace the section with the missing-data template from §6.

4. **Format** — Plain text by default; `?format=docx` for DOCX via pandoc (journal-ready formatting with Times New Roman 12pt, 1.5-inch margins, single-spaced paragraphs).

---

## 8. Data Quality at 20 Micrographs

For the CE-1 test run (20 EMPIAR-10028 micrographs), the report must include this caveat:

> **Data quantity note:** This analysis was performed on a subset of 20 micrographs from EMPIAR-10028 (beta-galactosidase), representing 1.9% of the full dataset (1,081 micrographs). At this data quantity (~25,000 picked particles), resolution is expected to be 15–25 Å. A minimum of 200 micrographs (>200,000 particles) is recommended for a map resolution sufficient for structural interpretation. These results are intended to validate the BioMate pipeline architecture, not to produce a publication-quality reconstruction.

---

## 9. Relationship to Existing Implementation

- `frontend/server/routes.ts` lines ~3750–4040: LLM generation endpoint (update to follow this protocol)
- `backend/biomni_workflows/.../cryosparc_standard_spa/main.nf`: pipeline that generates input JSONs
- `docs/20260416_CRYOSPARC_EXECUTE_FIXES_AND_REPORT_UPGRADE.md`: original 10-section spec

This protocol supersedes the ad-hoc section ordering and makes data extraction explicit.
