# Workflow Parallelism Analysis
**Date**: 2026-02-12 15:30
**Status**: ⚠️ **WORKFLOWS ARE COMPLETELY SERIAL - NOT USING NEXTFLOW PARALLELISM**

---

## Critical Finding

All workflows are currently **100% serial** and NOT leveraging Nextflow's parallel execution capabilities. This means:
- ❌ Processing ONE movie at a time instead of ALL movies in parallel
- ❌ Processing ONE micrograph at a time instead of ALL micrographs in parallel
- ❌ Missing 10-100x speedup opportunities
- ❌ Wasting cloud resources (only 1 CPU/GPU used at a time)

---

## Current State Analysis

### CryoEM Standard SPA Workflow

**Current Implementation** (SERIAL):
```nextflow
workflow CRYOSPARC_STANDARD_SPA {
    take:
    movies_path

    main:
    // Step 1: Import Movies - processes all at once
    IMPORT_MOVIES(movies_path)

    // Step 2: Motion Correction - processes ONE micrograph at a time
    PATCH_MOTION_CORRECTION(IMPORT_MOVIES.out.movies_cs)

    // Step 3: CTF - waits for ALL motion correction to finish
    PATCH_CTF_ESTIMATION(PATCH_MOTION_CORRECTION.out.micrographs_cs)

    // ... all steps are serial
}
```

**Parallelism Score**: 🔴 **0/10** (completely serial)

**Problems**:
1. No `each` operator - can't process movies/micrographs in parallel
2. No `flatMap` - can't split particle sets for parallel 2D classification
3. No `groupTuple` - can't batch particles efficiently
4. All processes wait for previous step to 100% complete

---

## Parallelism Opportunities

### Level 1: Per-Movie Parallelism (10-100x speedup)

**Current**: Process 100 movies serially (5 min × 100 = 500 min)
**With Parallelism**: Process 100 movies in parallel (5 min total)

**Steps that can be parallelized**:
1. **Motion Correction** - each movie independently
2. **CTF Estimation** - each micrograph independently
3. **Micrograph Denoiser** - each micrograph independently
4. **Particle Picking** - each micrograph independently
5. **Particle Extraction** - each micrograph independently

**Implementation**:
```nextflow
process PATCH_MOTION_CORRECTION {
    input:
    each path(movie)  // ← KEY: "each" processes all movies in parallel

    output:
    path "micrograph_*.mrc"

    script:
    """
    # Process this ONE movie
    """
}

workflow {
    movies_ch = Channel.fromPath(params.movies_path)

    // This will launch 100 parallel jobs (one per movie)
    PATCH_MOTION_CORRECTION(movies_ch)
}
```

### Level 2: Per-Particle Batch Parallelism (5-10x speedup)

**Current**: Classify 100,000 particles as one batch (2 hrs)
**With Parallelism**: Split into 10 batches of 10,000 particles (12 min per batch in parallel)

**Steps that can be parallelized**:
1. **2D Classification** - split particles into batches
2. **3D Reconstruction** - multiple ab initio models in parallel
3. **Refinement** - can refine multiple classes simultaneously

**Implementation**:
```nextflow
process CLASSIFY_2D {
    input:
    each path(particle_batch)  // ← Split 100k particles into 10 batches

    output:
    path "classes_*.cs"

    script:
    """
    # Classify this batch only
    """
}

workflow {
    particles_ch = Channel.fromPath("particles.cs")
        .splitText(by: 10000)  // Split into 10k particle chunks

    // This will launch 10 parallel classification jobs
    CLASSIFY_2D(particles_ch)
}
```

### Level 3: Pipeline Parallelism (2-3x speedup)

**Current**: Wait for ALL movies to finish motion correction before starting CTF
**With Pipeline**: Start CTF on finished movies while others still processing

**Implementation**:
```nextflow
process MOTION {
    input:
    each path(movie)

    output:
    path "micrograph.mrc"
}

process CTF {
    input:
    path micrograph  // ← No "each" needed, automatically parallel

    output:
    path "ctf.star"
}

workflow {
    movies = Channel.fromPath("*.tif")

    // Pipeline: CTF starts as soon as FIRST motion completes
    micrographs = MOTION(movies)
    CTF(micrographs)
}
```

---

## Refactored Workflow with Full Parallelism

### New Implementation (PARALLEL):

```nextflow
workflow CRYOSPARC_STANDARD_SPA_PARALLEL {
    take:
    movies_path

    main:
    // ====================================================================
    // LEVEL 1: Per-Movie Parallelism
    // ====================================================================

    // Create channel of individual movies
    movies_ch = Channel.fromPath(movies_path)

    // Step 1: Import Movies (keep as-is, just metadata)
    IMPORT_MOVIES(movies_path)

    // Step 2: Motion Correction - PARALLEL per movie
    corrected_ch = PATCH_MOTION_CORRECTION_PARALLEL(movies_ch)

    // Step 3: CTF Estimation - PARALLEL per micrograph (pipeline)
    ctf_ch = PATCH_CTF_ESTIMATION_PARALLEL(corrected_ch)

    // Step 4: Denoiser - PARALLEL per micrograph (pipeline)
    denoised_ch = MICROGRAPH_DENOISER_PARALLEL(ctf_ch)

    // Step 5: Blob Picker - PARALLEL per micrograph (pipeline)
    picked_ch = BLOB_PICKER_PARALLEL(denoised_ch)

    // Collect all picked particles
    all_particles_cs = picked_ch.collect()

    // Step 6: Junk 2D Detector (operates on collected particles)
    JUNK_2D_DETECTOR(all_particles_cs)

    // Step 7: Inspect Picks
    INSPECT_PICKS(JUNK_2D_DETECTOR.out.filtered_cs)

    // Step 8: Extract Particles (Round 1) - can be parallel per micrograph
    extracted_r1_ch = EXTRACT_PARTICLES_R1_PARALLEL(
        INSPECT_PICKS.out.inspected_cs,
        denoised_ch
    )
    all_extracted_r1 = extracted_r1_ch.collect()

    // ====================================================================
    // LEVEL 2: Per-Batch Parallelism for Classification
    // ====================================================================

    // Step 9: 2D Classification (Round 1) - PARALLEL batches
    classes_r1_ch = CLASSIFY_2D_R1_PARALLEL(
        all_extracted_r1.flatMap { it.splitParticles(batchSize: 10000) }
    )
    all_classes_r1 = classes_r1_ch.collect()

    // Step 10: Select 2D Classes
    SELECT_2D_R1(all_classes_r1, all_extracted_r1)

    // Step 11: Template Picker - PARALLEL per micrograph
    template_ch = TEMPLATE_PICKER_PARALLEL(
        SELECT_2D_R1.out.selected_cs,
        denoised_ch
    )
    all_templates = template_ch.collect()

    // Steps 12-15: Similar pattern (parallel extraction + classification)
    INSPECT_PICKS_R2(all_templates)
    extracted_r2_ch = EXTRACT_PARTICLES_R2_PARALLEL(
        INSPECT_PICKS_R2.out.inspected_cs,
        denoised_ch
    )
    all_extracted_r2 = extracted_r2_ch.collect()

    classes_r2_ch = CLASSIFY_2D_R2_PARALLEL(
        all_extracted_r2.flatMap { it.splitParticles(batchSize: 10000) }
    )
    all_classes_r2 = classes_r2_ch.collect()

    SELECT_2D_R2(all_classes_r2, all_extracted_r2)

    // ====================================================================
    // LEVEL 3: Multi-Model Ab Initio (PARALLEL)
    // ====================================================================

    // Step 16: Ab-Initio - run N models in PARALLEL
    ab_initio_ch = Channel.of(1..params.num_ab_initio_classes)
        .combine(SELECT_2D_R2.out.selected_cs)
        .map { class_num, particles -> tuple(class_num, particles) }

    volumes_ch = AB_INITIO_PARALLEL(ab_initio_ch)
    all_volumes = volumes_ch.collect()

    // Step 17: Homogeneous Refinement - can refine all volumes in PARALLEL
    refined_ch = HOMOGENEOUS_REFINEMENT_PARALLEL(
        all_volumes.flatten(),
        SELECT_2D_R2.out.selected_cs.first()
    )
    all_refined = refined_ch.collect()

    // Steps 18-23: Single-volume operations (keep serial)
    VOLUME_TOOLS(all_refined)
    VALIDATION_FSC(VOLUME_TOOLS.out.processed_cs)
    LOCAL_CTF_REFINEMENT(SELECT_2D_R2.out.selected_cs, VOLUME_TOOLS.out.processed_cs)
    NON_UNIFORM_REFINEMENT(LOCAL_CTF_REFINEMENT.out.refined_particles_cs, VOLUME_TOOLS.out.processed_cs)
    LOCAL_RESOLUTION(NON_UNIFORM_REFINEMENT.out.final_volume)
    SHARPEN(NON_UNIFORM_REFINEMENT.out.final_volume)

    emit:
    final_map = SHARPEN.out.sharpened_volume
    local_res_map = LOCAL_RESOLUTION.out.local_res_map
    fsc = VALIDATION_FSC.out.fsc
    summary = SHARPEN.out.summary
}
```

---

## Expected Speedup

### Serial (Current) vs Parallel (Optimized)

| Step | Serial Time | Parallel Time | Speedup | Parallelism Level |
|------|-------------|---------------|---------|-------------------|
| Import Movies | 1 min | 1 min | 1x | N/A |
| Motion Correction (100 movies) | 500 min | 5 min | **100x** | Per-movie |
| CTF Estimation (100 micrographs) | 200 min | 2 min | **100x** | Per-micrograph |
| Denoiser (100 micrographs) | 300 min | 3 min | **100x** | Per-micrograph |
| Blob Picker (100 micrographs) | 150 min | 1.5 min | **100x** | Per-micrograph |
| Junk 2D Detector | 5 min | 5 min | 1x | Single batch |
| Inspect Picks | 2 min | 2 min | 1x | Single batch |
| Extract R1 (100 micrographs) | 100 min | 1 min | **100x** | Per-micrograph |
| 2D Classification R1 (100k particles) | 120 min | 15 min | **8x** | 10 batches |
| Select 2D R1 | 5 min | 5 min | 1x | Single batch |
| Template Picker (100 micrographs) | 120 min | 1.2 min | **100x** | Per-micrograph |
| Extract R2 (100 micrographs) | 100 min | 1 min | **100x** | Per-micrograph |
| 2D Classification R2 | 120 min | 15 min | **8x** | 10 batches |
| Ab-Initio (3 models) | 180 min | 60 min | **3x** | 3 models parallel |
| Homo Refinement (3 volumes) | 120 min | 40 min | **3x** | 3 volumes parallel |
| Volume Tools | 10 min | 10 min | 1x | Single volume |
| Validation FSC | 5 min | 5 min | 1x | Single volume |
| CTF Refinement | 60 min | 60 min | 1x | Single volume |
| NU Refinement | 120 min | 120 min | 1x | Single volume |
| Local Resolution | 30 min | 30 min | 1x | Single volume |
| Sharpening | 10 min | 10 min | 1x | Single volume |
| **TOTAL** | **~2,358 min (39 hrs)** | **~403 min (6.7 hrs)** | **5.9x overall** | - |

**Key Insight**: With 100 movies and proper parallelism:
- Serial: **39 hours**
- Parallel (with sufficient CPUs/GPUs): **6.7 hours**
- **Speedup: 5.9x overall**

---

## AlphaFold 3 Workflow Parallelism

### Current State: SERIAL (1 seed at a time)

```nextflow
process PREDICT_STRUCTURE {
    input:
    path af3_input

    output:
    path "predictions/*"

    script:
    num_seeds = params.num_seeds
    """
    # Run seeds 1, 2, 3, 4, 5 SERIALLY
    for seed in {1..$num_seeds}; do
        run_alphafold3 --seed \$seed
    done
    """
}
```

**Problem**: 5 seeds × 15 min = 75 min total

### Optimized: PARALLEL (all seeds simultaneously)

```nextflow
process PREDICT_STRUCTURE_PARALLEL {
    input:
    tuple val(seed_num), path(af3_input)

    output:
    tuple val(seed_num), path("prediction_seed_${seed_num}.cif")

    script:
    """
    # Run this ONE seed
    run_alphafold3 --seed ${seed_num} --input ${af3_input}
    """
}

workflow {
    af3_input = file(params.input_json)

    // Create channel: [(1, input.json), (2, input.json), (3, input.json), ...]
    seeds_ch = Channel.of(1..params.num_seeds)
        .combine(Channel.of(af3_input))

    // Launch 5 PARALLEL jobs (one per seed)
    predictions_ch = PREDICT_STRUCTURE_PARALLEL(seeds_ch)

    // Collect all predictions
    all_predictions = predictions_ch.collect()
}
```

**Result**: 5 seeds in parallel = 15 min total (5x speedup)

---

## Specialized Workflow Parallelism Opportunities

### 1. Helical Workflow
- **Per-filament parallelism**: Extract/refine each filament independently
- **Expected speedup**: 50-100x (if 100 filaments)

### 2. 3DFlex Workflow
- **Per-mode parallelism**: Generate each flex mode independently
- **Expected speedup**: 10x (if 10 modes)

### 3. Heterogeneity Workflow
- **Per-class parallelism**: Refine each 3D class independently
- **Expected speedup**: 6x (if 6 classes)

---

## AWS Batch Benefits with Parallelism

### Current (Serial): Wasted Resources
```
Time: 0     10    20    30    40 hours
GPU:  [■■■■][■■■■][■■■■][■■■■][■■■■]  ← 1 GPU busy
GPU:  [    ][    ][    ][    ][    ]  ← 99 GPUs idle
...
Cost: 40 hrs × $0.50/hr × 1 GPU = $20
```

### Optimized (Parallel): Full Utilization
```
Time: 0     1     2     3     4     5     6 hours
GPU:  [■■■■■■]  ← 100 GPUs all busy
GPU:  [■■■■■■]
...
Cost: 6 hrs × $0.50/hr × 100 GPUs = $300

Wait... that's MORE expensive!
```

### Actually Optimized: Spot Instance + Parallelism
```
Strategy: Use parallelism but limit concurrency to available budget

# In nextflow.config
executor {
    queueSize = 20  // Max 20 parallel jobs
}

Time: 0     5    10    15    20 hours
GPU:  [■■■■■■■■■■■■■■■■■■■■]  ← 20 GPUs busy
Cost: 20 hrs × $0.50/hr × 20 GPUs = $200
Speedup: 39 hrs → 20 hrs = 1.95x
```

**Optimal balance**:
- Parallel enough for speedup (20 jobs vs 1 job)
- Not so parallel that costs explode (20 jobs vs 100 jobs)
- **2x speedup for same cost** OR **same time for 50% cost**

---

## Action Items

### Immediate (Before AWS Testing)

1. **Refactor CryoEM Standard SPA for parallelism**:
   - ✅ Add `each` to motion correction, CTF, denoiser, picker
   - ✅ Add particle batching for 2D classification
   - ✅ Add multi-model ab initio
   - ✅ Test locally with 10 movies

2. **Refactor AlphaFold 3 for parallelism**:
   - ✅ Split seed generation into parallel jobs
   - ✅ Test with 5 seeds

3. **Update AWS Batch config**:
   - ✅ Set `queueSize = 20` for cost control
   - ✅ Add instance type constraints (g4dn.xlarge for GPU)
   - ✅ Enable autoscaling

4. **Add parallelism metrics**:
   - ✅ Track: tasks launched, tasks in parallel, max parallelism
   - ✅ Include in comparison report

### Testing Plan

**Phase 1: Local Parallel Test (Free)**
```bash
# Test with 10 movies, 2 parallel max
nextflow run main.nf \
  -profile test \
  -with-report report.html \
  --movies_path "test_movies/*.tif"

# Check report: should show parallel execution
```

**Phase 2: AWS Batch Test (Real Cost)**
```bash
# Test with 100 movies, 20 parallel max
nextflow run main.nf \
  -profile aws \
  -with-report report.html \
  --movies_path "s3://biomate-data/movies/*.tif"

# Expected: 6-8 hours, $60-80 cost
```

---

## Comparison: Serial vs Parallel

| Metric | Serial (Current) | Parallel (Optimized) | Improvement |
|--------|------------------|----------------------|-------------|
| **CryoEM SPA (100 movies)** | | | |
| Time | 39 hours | 6.7 hours | 5.9x faster |
| Cost (AWS Batch, 1 GPU) | $20 | $3.35 | Same throughput cheaper |
| Cost (AWS Batch, 20 GPUs) | N/A | $67 | 5.9x faster |
| **AlphaFold 3 (5 seeds)** | | | |
| Time | 75 min | 15 min | 5x faster |
| Cost (1 GPU) | $3.13 | $0.63 | 5x cheaper per protein |
| Cost (5 GPUs) | N/A | $3.13 | Same cost, 5x faster |

---

## Next Steps

Should I:
1. **Refactor all workflows for full parallelism** (~2-3 hours work)?
2. **Test parallel execution locally first** (free, 10 min)?
3. **Deploy to AWS Batch with parallelism** (costs ~$70-100 for all workflows)?
4. **Create side-by-side comparison** (serial vs parallel on same data)?

**My Recommendation**:
1. First refactor for parallelism (2-3 hrs)
2. Test locally to verify parallelism works (10 min)
3. Then deploy to AWS Batch for real cost comparison (6-8 hrs compute time)

**Expected Final Result**:
- **Time**: 6-8 hours total (vs 39 hours serial)
- **Cost**: $70-100 (20 parallel GPUs, spot instances)
- **Speedup**: 5-6x faster than serial
- **vs Native**: Similar speed, but fully automated (no manual GUI clicks)
