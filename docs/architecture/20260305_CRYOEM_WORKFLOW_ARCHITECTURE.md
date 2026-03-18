# Cryo-EM Workflow Architecture — Current State
**Date:** 2026-03-05
**Status:** Production (cryo_em/ + cryo_et/) and newly added modules
**Audience:** Engineers, collaborators, pipeline developers

---

## 1. Repository Layout

All cryo-EM and cryo-ET workflows live under:

```
backend/biomni_workflows/nextflow_nfcore/subworkflows/
  cryo_em/          ← 15 SPA-related workflow files
  cryo_et/          ← 5 ET-related workflow files
```

There is no shared `modules/` layer. Every file is self-contained: it declares its own processes with inline Python scripts and its own `params` block. There is no `include` statement anywhere in the cryo-EM or cryo-ET subworkflows.

---

## 2. Cryo-EM (SPA) Workflows — Full Inventory

### 2.1 Standard SPA Monolith

**File:** `cryo_em/cryosparc_standard_spa/main.nf`
**Size:** 1,612 lines
**Type:** Monolith — all 23 processes inlined in a single file

| Step | Process name | QC gate | Output |
|---|---|---|---|
| 1 | `IMPORT_MOVIES` | — | `movies_imported.cs` |
| 2 | `PATCH_MOTION_CORRECTION` | drift < 50 Å [GOLD] | `micrographs_corrected.cs`, `motion_report.json` |
| 3 | `PATCH_CTF_ESTIMATION` | fit_quality ≥ 0.7 [GOLD]; VPP phase 0.2–1.5 rad | `micrographs_ctf.cs`, `ctf_report.json` |
| 4 | `MICROGRAPH_DENOISER` | — | `micrographs_denoised.cs` |
| 5 | `BLOB_PICKER` | particles_picked ≥ 1,000 | `picks_r1.cs`, `picking_report.json` |
| 6 | `JUNK_2D_DETECTOR` | — | `picks_filtered.cs` |
| 7 | `INSPECT_PICKS` | — | `picks_inspected.cs` |
| 8 | `EXTRACT_PARTICLES_R1` | — | `particles_r1.cs` |
| 9 | `CLASSIFY_2D_R1` | junk_fraction < 70% [GOLD] | `classes_r1.cs`, `classify_report.json` |
| 10 | `SELECT_2D_R1` | — | `selected_particles_r1.cs` |
| 11 | `TEMPLATE_PICKER` | particles_picked ≥ 1,000 | `picks_r2.cs` |
| 12 | `INSPECT_PICKS_R2` | — | `picks_r2_inspected.cs` |
| 13 | `EXTRACT_PARTICLES_R2` | — | `particles_r2.cs` |
| 14 | `CLASSIFY_2D_R2` | junk_fraction < 70% [GOLD] | `classes_r2.cs` |
| 15 | `SELECT_2D_R2` | — | `selected_particles_r2.cs` |
| 16 | `AB_INITIO` | — | `volumes.cs` |
| 17 | `HOMOGENEOUS_REFINEMENT` | anisotropy < 10× [GOLD]; < 5× [SILVER] | `refined_volume.cs`, `refinement_report.json` |
| 18 | `VOLUME_TOOLS` | — | `volume_processed.cs` |
| 19 | `VALIDATION_FSC` | fsc_0143_resolution logged | `fsc_validation.json` |
| 20 | `LOCAL_CTF_REFINEMENT` | — | `particles_ctf_refined.cs` |
| 21 | `NON_UNIFORM_REFINEMENT` | — | `nu_refined_volume.cs` |
| 22 | `LOCAL_RESOLUTION` | σ spread advisory [BRONZE] | `local_resolution.cs` |
| 23 | `SHARPEN` | B-factor −300–0 Å² advisory | `sharpened_map.cs`, `sharpening_report.json` |

**Key params:** `pixel_size`, `voltage`, `cs`, `total_dose`, `symmetry`, `phase_plate`, `sample_type`, `qc_profile`, `mock_mode`, `use_cryosparc`

**Execution mode:** `params.mock_mode = true` (default) runs Python inline simulations; `params.use_cryosparc = true` calls live CryoSPARC API via `cryosparc-tools`.

---

### 2.2 Helical SPA Monolith

**File:** `cryo_em/helical_spa_pipeline/main.nf`
**Size:** 958 lines
**Type:** Monolith — 11 processes inlined; re-duplicates IMPORT_MOVIES, PATCH_MOTION_CORRECTION, PATCH_CTF_ESTIMATION from the SPA monolith

| Step | Process name | Purpose |
|---|---|---|
| 1 | `IMPORT_MOVIES` | Same as SPA — duplicated inline |
| 2 | `PATCH_MOTION_CORRECTION` | Same as SPA — duplicated inline |
| 3 | `PATCH_CTF_ESTIMATION` | Same as SPA — duplicated inline |
| 4 | `FILAMENT_TRACER` | Traces filament axes; picks along helical repeat |
| 5 | `EXTRACT_HELICAL_PARTICLES` | Extracts overlapping helical segments |
| 6 | `CLASSIFY_2D_HELICAL` | 2D classification of helical segments |
| 7 | `SELECT_2D_HELICAL` | Selects high-quality 2D classes |
| 8 | `AB_INITIO_HELICAL` | Generates initial helical volume |
| 9 | `HELICAL_REFINEMENT` | Applies helical symmetry (rise + twist) |
| 10 | `HELICAL_SHARPENING` | B-factor sharpening |
| 11 | `HELICAL_PIPELINE_SUMMARY` | Aggregates metrics |

**Key params:** `filament_diameter_angstroms`, `helical_rise_angstroms`, `helical_twist_deg`, `refine_helical_params`
**Config:** `helical_spa_pipeline/nextflow.config` — profiles: test, docker, singularity, local\_gpu, slurm

---

### 2.3 Standalone Advanced SPA Modules

Each of these is a self-contained single-process file designed to be run after the standard SPA pipeline produces output.

| Module | File | Lines | Process | Input ports | Output ports |
|---|---|---|---|---|---|
| Particle subtraction | `particle_subtraction/main.nf` | 176 | `PARTICLE_SUBTRACTION` | `particles_cs`, `volume_cs` | `subtracted_particles.cs`, `subtraction_report.json` |
| Local refinement | `local_refinement/main.nf` | 175 | `LOCAL_REFINEMENT` (GPU) | `subtracted_particles_cs`, `volume_cs` | `local_refined_volume.cs`, `local_refinement_report.json` |
| 3D variability analysis | `3d_variability_analysis/main.nf` | 204 | `THREE_D_VARIABILITY` (GPU) | `particles_cs`, `volume_cs` | `particles_with_latent.cs`, `3dva_report.json`, `variability_component_N.cs` |
| Symmetry expansion | `symmetry_expansion/main.nf` | 251 | `SYMMETRY_EXPANSION` | `particles_cs`, `volume_cs` | `symmetry_expanded_particles.cs`, `symmetry_expansion_report.json` |
| Global CTF refinement | `global_ctf_refinement/main.nf` | 265 | `GLOBAL_CTF_REFINEMENT` | `particles_cs`, `volume_cs` | `particles_global_ctf.cs`, `global_ctf_report.json` |
| Filament tracer | `filament_tracer/main.nf` | 220 | `FILAMENT_TRACER` | `micrographs_ctf_cs` | `filament_picks.cs`, `filament_tracer_report.json` |
| Helical refinement | `helical_refinement/main.nf` | 196 | `HELICAL_REFINEMENT` (GPU) | `particles_cs`, `volume_cs` | `helical_volume.cs`, `helical_refinement_report.json` |
| Import micrographs | `import_micrographs/main.nf` | 168 | `IMPORT_MICROGRAPHS` | *(reads params.micrographs_path)* | `micrographs_imported.cs`, `import_micrographs_report.json` |
| Import particles | `import_particles/main.nf` | 181 | `IMPORT_PARTICLES` | *(reads params.particle_star / params.particle_cs)* | `particles_imported.cs`, `import_particles_report.json` |
| Topaz train | `topaz_train/main.nf` | 200 | `TOPAZ_TRAIN` (GPU) | `micrographs_cs`, `particles_cs` | `topaz_model.pth`, `topaz_train_report.json` |
| Topaz extract | `topaz_extract/main.nf` | 186 | `TOPAZ_EXTRACT` (GPU) | `micrographs_cs`, `topaz_model` | `topaz_picks.cs`, `topaz_extract_report.json` |

### 2.4 Composite SPA Pipeline Files

These orchestrate multiple standalone modules in sequence within a single DSL2 workflow block. They do NOT use `include` — they re-inline the process definitions.

| File | Orchestrates | Lines |
|---|---|---|
| `focused_refinement_pipeline/main.nf` | PARTICLE_SUBTRACTION → LOCAL_REFINEMENT → FOCUSED_REFINEMENT_SUMMARY | 375 |
| `3d_variability_pipeline/main.nf` | THREE_D_VARIABILITY → THREE_D_VARIABILITY_DISPLAY | 356 |

---

## 3. Cryo-ET Workflows — Full Inventory

**Location:** `cryo_et/`

| Module | File | Lines | Process(es) | Input | Output |
|---|---|---|---|---|---|
| Import tilt series | `import_tiltseries/main.nf` | 158 | `IMPORT_TILTSERIES` | MDOC + MRC directory | `tiltseries_imported.json` |
| Tilt alignment | `tilt_alignment/main.nf` | 171 | `TILT_ALIGNMENT` (GPU) | `tiltseries_imported.json` | `tilt_alignment_report.json`, per-tilt transforms |
| Tomogram reconstruction | `tomogram_reconstruction/main.nf` | 148 | `TOMOGRAM_RECONSTRUCTION` | alignment report | `tomogram_reconstruction_report.json`, tomogram MRCs |
| Subtomogram averaging | `subtomogram_averaging/main.nf` | 149 | `SUBTOMOGRAM_AVERAGING` | tomograms + template | `sta_report.json`, STA map |
| ET full pipeline | `et_full_pipeline/main.nf` | 650 | All 4 processes + `ET_PIPELINE_SUMMARY` | MDOC + MRC directory | `et_pipeline_summary.json` |

**ET config:** `et_full_pipeline/nextflow.config` — profiles: test, docker, singularity, stub, local\_gpu, slurm

**ET QC gates** (in `qc_trace_monitor.py`):
- `TILT_ALIGNMENT`: mean residual > 5 Å → SILVER advisory
- `SUBTOMOGRAM_AVERAGING`: FSC > 50 Å → SILVER advisory; 30–50 Å → BRONZE advisory (Rosenthal & Henderson 2003)

**ET parallelism:** All tilt series processed simultaneously — each is a separate Nextflow channel item in `TILT_ALIGNMENT` and `TOMOGRAM_RECONSTRUCTION`.

---

## 4. Data Format: The `.cs` Convention

In mock mode, `.cs` files are JSON. Their schemas are informally defined per-pipeline:

| Logical type | Typical keys | Used by |
|---|---|---|
| Micrograph set | `{micrographs: [{filename, pixel_size, defocus_u, defocus_v, ctf_fom, ...}]}` | CTF, picking |
| Particle stack | `{particles: [{x, y, defocus_u, defocus_v, psi, phi, theta, ...}]}` | Classification, refinement |
| Volume | `{volume: {resolution_angstroms, symmetry, fsc_0143_resolution}}` | Refinement, post-processing |
| Filament picks | `{picks: [{micrograph_idx, x, y, filament_id, angle_deg}], num_filaments, num_picks}` | Helical extraction |

There is no formal JSON schema enforcing these structures. No pipeline validates that its input files conform to the expected structure.

---

## 5. How the AI Invokes Workflows

1. User describes experiment in plain English
2. AI generates a `workflow_artifact` with:
   - `nextflow_path`: absolute path to a `main.nf`
   - `parameters`: flat dict of `params.*` values
   - `execution_config`: executor, GPU count, S3 bucket
3. Frontend `POST /api/nextflow/execute` → `nextflow_executor_v2.py` → `runner.queue_job(nextflow_path, parameters)`
4. SSE stream returns QC gate events and progress

**There is no automatic path resolution between pipelines.** If a user runs SPA and then wants focused refinement, the AI must manually insert the output paths from the SPA run into the focused refinement parameters. This is done from conversation context — the AI has the prior invocation's `outdir` but has no manifest to tell it which file is `particles_cs` vs `volume_cs`.

---

## 6. Known Structural Problems

| Problem | Impact | Affected files |
|---|---|---|
| **No output manifests** | AI cannot auto-resolve downstream inputs; multi-pipeline projects require manual path stitching | All 20 workflows |
| **Code duplication** | IMPORT_MOVIES, PATCH_MOTION_CORRECTION, PATCH_CTF_ESTIMATION appear in both SPA monolith and helical pipeline | `cryosparc_standard_spa/`, `helical_spa_pipeline/` |
| **No port type schema** | Can't validate that output of pipeline A is compatible with input of pipeline B | All workflows |
| **Monolith architecture** | Can't run step 5–10 of SPA independently; must re-run from scratch if upstream fails after step 15 | `cryosparc_standard_spa/`, `helical_spa_pipeline/` |
| **ET and SPA not connected** | STA map cannot directly feed into local_refinement or molprobity without manual path insertion | `cryo_et/`, `cryo_em/local_refinement/` |
| **No resume across pipelines** | Nextflow `-resume` works within one pipeline; does not help with multi-pipeline chains | All |

---

## 7. QC Governance Integration

All cryo-EM QC gates live in:
`backend/lib/galaxy/jobs/qc_trace_monitor.py`

The monitor is **not invoked by Nextflow directly**. It runs in the Galaxy/BioMate backend, reading JSON report files produced by the Nextflow processes and emitting SSE events. The connection is:

```
Nextflow process → writes JSON report → qc_trace_monitor reads report → emits SSE to frontend
```

**Dispatch table** (process name prefix → parser method):

| Process prefix | Parser method | QC gates |
|---|---|---|
| `PATCH_MOTION` | `_parse_motion_metrics()` | drift, per-frame |
| `PATCH_CTF`, `CTF_EST` | `_parse_ctf_metrics()` | fit_quality, astigmatism, ice, VPP phase |
| `CLASSIFY_2D` | `_parse_2d_classification_metrics()` | junk fraction |
| `HOMOGENEOUS_REFINE` | `_parse_refinement_metrics()` | FSC, anisotropy |
| `NON_UNIFORM_REFINE` | `_parse_refinement_metrics()` | FSC |
| `LOCAL_RESOLUTION` | `_parse_local_resolution_metrics()` | σ spread |
| `SHARPEN` | `_parse_sharpening_metrics()` | B-factor |
| `TILT_ALIGNMENT` | `_parse_tilt_alignment_metrics()` | alignment residual |
| `SUBTOMOGRAM_AVG` | `_parse_sta_metrics()` | FSC resolution |
| `MOLPROBITY` | `_parse_model_quality_metrics()` | Ramachandran, rotamer, clashscore |
| `EMRINGER` | `_parse_model_quality_metrics()` | EMRinger score |

**Named QC profiles (cryo-EM):** `cryoem_spa_standard`, `cryoem_spa_purified`, `cryoem_spa_membrane`, `cryoem_spa_phase_plate`, `cryoem_spa_lowdose`

---

## 8. Summary: What Exists vs. What Is Wired

```
EXISTS                          WIRED (actually connected)
──────                          ──────────────────────────
20 workflow files               ✓ AI can invoke any single pipeline
15 SPA processes                ✓ QC monitor parses their JSON outputs
5 ET processes                  ✓ ET QC gates (alignment residual, STA FSC)
5 cryo-EM QC profiles           ✓ Profile overrides applied per-invocation
Mock mode for all               ✓ All pipelines testable without CryoSPARC/GPU

NOT WIRED
─────────
Output manifests                ✗ No pipeline writes workflow_outputs.json
Port schema registry            ✗ No central registry of input/output types
Auto-resolution of upstream     ✗ No cross-invocation path lookup
ET → SPA post-processing        ✗ STA map cannot auto-feed local_refinement
Multi-team project graph        ✗ No dependency DAG at the project level
nf-core include/import          ✗ No module reuse; code duplicated
```
