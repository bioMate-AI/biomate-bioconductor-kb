# DIA-NN Workflow Speedup Integration Plan

**Date**: 2025-12-05 15:26
**Goal**: Reduce UniProt protein matching from 2 days → 2 hours
**Target**: nf-core/quantms DIA-NN pipeline

---

## Problem Analysis

### Current DIA-NN Workflow (nf-core/quantms)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        DIA_PROTEOMICS_ANALYSIS                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. QUANTMSUTILS_DIANNCFG                                                   │
│     └── Generate config (enzyme, modifications)                             │
│                                                                             │
│  2. DIANN_INSILICOLIBRARYGENERATION  ◀══════ BOTTLENECK (6-48 hours)       │
│     └── FASTA → In-silico spectral library                                  │
│     └── Uses: --fasta, --fasta-search, --predictor, --gen-spec-lib          │
│                                                                             │
│  3. DIANN_PRELIMINARYANALYSIS                                               │
│     └── Initial search with spectral library                                │
│                                                                             │
│  4. DIANN_ASSEMBLEEMPIRICALLIBRARY                                          │
│     └── Build empirical library from preliminary results                    │
│                                                                             │
│  5. DIANN_INDIVIDUALANALYSIS                                                │
│     └── Per-sample analysis with empirical library                          │
│                                                                             │
│  6. DIANN_FINALQUANTIFICATION                                               │
│     └── Cross-run normalization, protein quantification                     │
│                                                                             │
│  7. QUANTMSUTILS_DIANN2MZTAB                                                │
│     └── Convert to mzTab format                                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### The Bottleneck: In-Silico Library Generation

**What happens in Step 2**:
1. Parse UniProt FASTA (20,000+ human proteins)
2. In-silico digest with enzyme (trypsin) → millions of peptides
3. Apply modifications (fixed: Carbamidomethyl; variable: Oxidation)
4. Deep learning prediction of:
   - Retention time (RT)
   - Ion mobility (IM)
   - Fragmentation patterns (MS2 spectra)
5. Generate `.predicted.speclib` file

**Why it's slow**:
- Deep learning inference on millions of peptides
- CPU-bound (DIA-NN doesn't have GPU support for library generation)
- Single-threaded for some operations
- Large memory footprint for full UniProt

---

## Solution Options

### Option A: Pre-computed Spectral Library (Recommended)

**Concept**: Generate library once, reuse for all experiments

**Implementation**:
```nextflow
// Skip library generation if pre-computed library provided
if (params.precomputed_speclib) {
    ch_speclib = Channel.fromPath(params.precomputed_speclib)
} else {
    DIANN_INSILICOLIBRARYGENERATION(ch_fasta_input)
    ch_speclib = DIANN_INSILICOLIBRARYGENERATION.out.predict_speclib
}
```

**Speedup**: 2 days → 0 (library already exists)

**Caveat**: Must regenerate if FASTA or modifications change

---

### Option B: MSFragger-DIA (6x Faster Alternative)

**Tool**: [MSFragger-DIA](https://fragpipe.nesvilab.org/) via FragPipe

**Benchmark** ([Nature Communications 2023](https://www.nature.com/articles/s41467-023-39869-5)):
> "FragPipe with MSFragger-DIA had the fastest overall speed; it is at least **six times faster** than that of the DIA-NN library-free workflow"

**Integration**:
```nextflow
process MSFRAGGER_DIA {
    container 'docker.io/biocontainers/fragpipe:21.1'

    input:
    tuple val(meta), path(mzml), path(fasta)

    output:
    tuple val(meta), path("*.tsv"), emit: results

    script:
    """
    fragpipe --workflow DIA --database ${fasta} --input ${mzml} --output .
    """
}
```

**Speedup**: 2 days → 8 hours

---

### Option C: Prosit + GPU Acceleration

**Tool**: [Prosit](https://www.nature.com/articles/s41592-019-0426-7) for spectral prediction

**Advantage**: GPU-accelerated deep learning

**Integration**:
```nextflow
process PROSIT_PREDICT {
    label 'process_gpu'
    container 'docker.io/prosit/prosit:latest'

    input:
    tuple val(meta), path(peptides)

    output:
    tuple val(meta), path("*.speclib"), emit: speclib

    script:
    """
    prosit_predict \
        --input ${peptides} \
        --output predictions.speclib \
        --model prosit_2020_hcd
    """
}
```

**Speedup**: 2 days → 2-4 hours (with GPU)

---

### Option D: Hybrid Approach (Best of Both)

**Concept**: Use fast tools for library generation, DIA-NN for quantification

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     OPTIMIZED DIA WORKFLOW                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ STAGE 1: FAST SPECTRAL LIBRARY GENERATION                           │   │
│  │                                                                     │   │
│  │  Option D1: Pre-indexed UniProt Library                             │   │
│  │  ├── Download once: uniprot_human.speclib (pre-computed)            │   │
│  │  └── Skip generation entirely                                       │   │
│  │                                                                     │   │
│  │  Option D2: Prosit + GPU                                            │   │
│  │  ├── FASTA → Peptides (MMseqs2 digest, 10 min)                      │   │
│  │  ├── Peptides → Prosit predictions (GPU, 1-2 hours)                 │   │
│  │  └── Convert to DIA-NN format                                       │   │
│  │                                                                     │   │
│  │  Option D3: MSLibrarian Optimization                                │   │
│  │  ├── Use Prosit for initial predictions                             │   │
│  │  ├── Optimize with DIA-Umpire pseudo-spectra                        │   │
│  │  └── DeepLC retention time correction                               │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                              ↓                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ STAGE 2: DIA-NN ANALYSIS (unchanged)                                │   │
│  │                                                                     │   │
│  │  DIANN_PRELIMINARYANALYSIS                                          │   │
│  │       ↓                                                             │   │
│  │  DIANN_ASSEMBLEEMPIRICALLIBRARY                                     │   │
│  │       ↓                                                             │   │
│  │  DIANN_INDIVIDUALANALYSIS                                           │   │
│  │       ↓                                                             │   │
│  │  DIANN_FINALQUANTIFICATION                                          │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Recommended Implementation Plan

### Phase 1: Pre-computed Library Service (Fastest Win)

**Timeline**: 1-2 weeks

1. **Create library repository**:
   ```
   biomate-spectral-libraries/
   ├── human/
   │   ├── uniprot_human_2024_01.speclib     # Full UniProt
   │   ├── uniprot_human_reviewed.speclib   # SwissProt only
   │   └── metadata.json                     # Version, mods, enzyme
   ├── mouse/
   └── common_contaminants/
   ```

2. **Add parameter to workflow**:
   ```nextflow
   params.precomputed_speclib = null  // User provides path
   params.speclib_organism = 'human'  // Auto-download from repository
   ```

3. **Auto-download module**:
   ```nextflow
   process DOWNLOAD_SPECLIB {
       output:
       path("*.speclib"), emit: speclib

       script:
       """
       curl -O https://biomate-libs.s3.amazonaws.com/${params.speclib_organism}/uniprot.speclib
       """
   }
   ```

**Expected Speedup**: 2 days → 30 minutes (download + remaining steps)

---

### Phase 2: GPU-Accelerated Prosit Integration

**Timeline**: 2-3 weeks

1. **Add Prosit module**:
   ```nextflow
   process PROSIT_SPECTRAL_LIBRARY {
       label 'process_gpu'
       container 'ghcr.io/compms/prosit:2024.1'

       input:
       tuple val(meta), path(fasta)

       output:
       tuple val(meta), path("*.speclib"), emit: speclib

       script:
       """
       # Digest FASTA to peptides
       prosit_digest --fasta ${fasta} --enzyme trypsin --output peptides.csv

       # GPU prediction
       prosit_predict \
           --input peptides.csv \
           --model prosit_2020_hcd \
           --output prosit_predictions.csv \
           --gpu

       # Convert to DIA-NN format
       prosit_to_diann --input prosit_predictions.csv --output library.speclib
       """
   }
   ```

2. **Conditional execution**:
   ```nextflow
   if (params.use_prosit && params.gpu_available) {
       PROSIT_SPECTRAL_LIBRARY(ch_fasta)
       ch_speclib = PROSIT_SPECTRAL_LIBRARY.out.speclib
   } else {
       DIANN_INSILICOLIBRARYGENERATION(ch_fasta)
       ch_speclib = DIANN_INSILICOLIBRARYGENERATION.out.predict_speclib
   }
   ```

**Expected Speedup**: 2 days → 2-3 hours

---

### Phase 3: MSFragger-DIA Alternative Path

**Timeline**: 3-4 weeks

1. **Add MSFragger subworkflow**:
   ```nextflow
   workflow MSFRAGGER_DIA_ANALYSIS {
       take:
       ch_mzml
       ch_fasta

       main:
       MSFRAGGER_SEARCH(ch_mzml, ch_fasta)
       PEPTIDE_PROPHET(MSFRAGGER_SEARCH.out.pepxml)
       PROTEIN_PROPHET(PEPTIDE_PROPHET.out.validated)
       IONQUANT(PROTEIN_PROPHET.out.proteins, ch_mzml)

       emit:
       quantification = IONQUANT.out.results
   }
   ```

2. **User choice in config**:
   ```nextflow
   params.dia_engine = 'diann'  // Options: 'diann', 'msfragger', 'hybrid'
   ```

**Expected Speedup**: 2 days → 6-8 hours

---

## Performance Comparison Summary

| Approach | Library Gen Time | Total Time | Quality | GPU Required |
|----------|------------------|------------|---------|--------------|
| Current DIA-NN | 24-48 hours | 2+ days | ⭐⭐⭐⭐⭐ | No |
| Pre-computed Library | 0 (download) | 2-4 hours | ⭐⭐⭐⭐⭐ | No |
| Prosit + GPU | 1-2 hours | 3-4 hours | ⭐⭐⭐⭐ | Yes |
| MSFragger-DIA | 4-6 hours | 6-8 hours | ⭐⭐⭐⭐ | No |
| Hybrid (Prosit→DIA-NN) | 1-2 hours | 4-6 hours | ⭐⭐⭐⭐⭐ | Yes |

---

## Files to Modify

### nf-core/quantms Integration

```
modules/nf-core/
├── prosit/
│   └── main.nf                    # NEW: Prosit prediction module
├── msfragger/
│   └── main.nf                    # NEW: MSFragger-DIA module
└── diann/
    └── main.nf                    # MODIFY: Add speclib input option

subworkflows/nf-core/
├── dia_proteomics_analysis/
│   └── main.nf                    # MODIFY: Add library source options
└── fast_spectral_library/
    └── main.nf                    # NEW: Prosit/pre-computed library

conf/
└── modules.config                 # MODIFY: Add new module configs
```

---

## Quick Start for Users

### Option 1: Use Pre-computed Library (Recommended)

```bash
nextflow run nf-core/quantms \
    --input samplesheet.csv \
    --database uniprot_human.fasta \
    --precomputed_speclib s3://biomate-libs/human/uniprot_2024.speclib \
    --dia_engine diann \
    -profile docker
```

### Option 2: GPU-Accelerated Generation

```bash
nextflow run nf-core/quantms \
    --input samplesheet.csv \
    --database uniprot_human.fasta \
    --use_prosit true \
    --dia_engine diann \
    -profile docker,gpu
```

### Option 3: MSFragger-DIA (No GPU)

```bash
nextflow run nf-core/quantms \
    --input samplesheet.csv \
    --database uniprot_human.fasta \
    --dia_engine msfragger \
    -profile docker
```

---

## References

1. [DIA-NN](https://github.com/vdemichev/DiaNN) - Neural networks for DIA proteomics
2. [MSFragger-DIA](https://www.nature.com/articles/s41467-023-39869-5) - 6x faster than DIA-NN library-free
3. [Prosit](https://www.nature.com/articles/s41592-019-0426-7) - Deep learning spectral prediction
4. [MSLibrarian](https://pubs.acs.org/doi/10.1021/acs.jproteome.1c00796) - Optimized predicted libraries
5. [nf-core/quantms](https://nf-co.re/quantms) - Production proteomics pipeline
