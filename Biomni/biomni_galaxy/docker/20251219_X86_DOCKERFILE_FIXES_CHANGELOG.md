# Dockerfile Fixes Changelog

**Date:** December 19, 2025
**Purpose:** Fix dependency issues discovered during verification testing

---

## Summary

After initial Docker image builds, verification testing revealed several dependency issues. This document records all fixes applied to ensure proper tool functionality.

---

## Dockerfile.wgs-wes

### 1. cnvkit pandas compatibility
**Problem:** `ImportError: cannot import name 'Int64Index' from 'pandas'`
**Cause:** pandas 2.0 removed Int64Index, but cnvkit still uses it
**Fix:** Pin pandas version
```dockerfile
# Before
RUN micromamba install -n biotools -c conda-forge -c bioconda -y \
    cnvkit \
    && micromamba clean --all -y || true

# After
RUN micromamba install -n biotools -c conda-forge -c bioconda -y \
    cnvkit "pandas<2.0" \
    && micromamba clean --all -y || true
```

### 2. snpEff Java LinkageError
**Problem:** `LinkageError occurred while loading main class org.snpeff.SnpEff`
**Cause:** Java version conflict with default JDK
**Fix:** Explicitly install compatible OpenJDK version
```dockerfile
# Before
RUN micromamba install -n biotools -c conda-forge -c bioconda -y \
    snpeff \
    && micromamba clean --all -y || true

# After
RUN micromamba install -n biotools -c conda-forge -c bioconda -y \
    snpeff openjdk=17 \
    && micromamba clean --all -y || true
```

### 3. Ensembl VEP missing Perl modules
**Problem:** `Can't locate DBI.pm in @INC`
**Cause:** Required Perl database modules not installed
**Fix:** Add perl-dbi and related modules
```dockerfile
# Before
RUN micromamba install -n biotools -c conda-forge -c bioconda -y \
    ensembl-vep \
    && micromamba clean --all -y || true

# After
RUN micromamba install -n biotools -c conda-forge -c bioconda -y \
    ensembl-vep perl-dbi perl-dbd-mysql perl-bio-db-hts \
    && micromamba clean --all -y || true
```

### 4. Missing Copy Number Analysis tools
**Problem:** nf-core/sarek requires Control-FREEC and ASCAT for copy number analysis
**Fix:** Add new section for copy number tools
```dockerfile
# Added new section
# ==============================================================================
# Copy Number Analysis (ASCAT, Control-FREEC)
# ==============================================================================
RUN micromamba install -n biotools -c conda-forge -c bioconda -y \
    control-freec \
    && micromamba clean --all -y || true

RUN micromamba install -n biotools -c conda-forge -c bioconda -y \
    r-ascat \
    && micromamba clean --all -y || true
```

### 5. Updated verification script
Added copy number analysis section to verify-tools.sh

---

## Dockerfile.rnaseq

### 1. OUTRIDER/FRASER installation failure
**Problem:** R packages silently failed to install via BiocManager
**Cause:** Complex R package dependencies not resolved properly
**Fix:** Use conda bioconductor packages instead
```dockerfile
# Before
RUN micromamba run -n biotools R -e "if (!require('BiocManager', quietly = TRUE)) install.packages('BiocManager'); BiocManager::install(c('OUTRIDER', 'FRASER'), ask=FALSE, update=FALSE)" || true

# After
RUN micromamba install -n biotools -c conda-forge -c bioconda -y \
    bioconductor-outrider bioconductor-fraser \
    && micromamba clean --all -y || true
```

### 2. Python packages via pip
**Problem:** pip installations can cause dependency conflicts
**Fix:** Use conda for consistent dependency management
```dockerfile
# Before
RUN micromamba run -n biotools pip install --no-cache-dir \
    numpy scipy pandas matplotlib seaborn \
    biopython pysam \
    || true

# After
RUN micromamba install -n biotools -c conda-forge -c bioconda -y \
    numpy scipy pandas matplotlib seaborn \
    biopython pysam \
    && micromamba clean --all -y || true
```

---

## Dockerfile.cutandrun

### 1. Python packages via pip
**Problem:** pip installations can cause dependency conflicts
**Fix:** Use conda for consistency with other images
```dockerfile
# Before
RUN micromamba run -n biotools pip install --no-cache-dir \
    numpy scipy pandas matplotlib seaborn \
    pybedtools pysam \
    || true

# After
RUN micromamba install -n biotools -c conda-forge -c bioconda -y \
    numpy scipy pandas matplotlib seaborn \
    pybedtools pysam \
    && micromamba clean --all -y || true
```

---

## Dockerfile.singlecell

### 1. kallisto missing libhdf5
**Problem:** `libhdf5.so.10: cannot open shared object file`
**Fix:** Add hdf5 as explicit dependency
```dockerfile
# Before
RUN micromamba install -n biotools -c conda-forge -c bioconda -y \
    salmon kallisto \
    && micromamba clean --all -y

# After
RUN micromamba install -n biotools -c conda-forge -c bioconda -y \
    salmon kallisto hdf5 \
    && micromamba clean --all -y
```

### 2. scanpy/anndata/leidenalg not installed
**Problem:** pip installation silently failed
**Fix:** Use conda with explicit dependencies
```dockerfile
# Before
RUN micromamba run -n biotools pip install --no-cache-dir \
    numpy scipy pandas matplotlib seaborn \
    scanpy anndata leidenalg \
    || true

# After
RUN micromamba install -n biotools -c conda-forge -c bioconda -y \
    numpy scipy pandas matplotlib seaborn \
    scanpy anndata leidenalg igraph \
    && micromamba clean --all -y
```

### 3. scrublet not installed
**Problem:** pip installation failed
**Fix:** Use conda
```dockerfile
# Before
RUN micromamba run -n biotools pip install --no-cache-dir \
    scrublet doubletdetection \
    || true

# After
RUN micromamba install -n biotools -c conda-forge -c bioconda -y \
    scrublet \
    && micromamba clean --all -y || true

# doubletdetection via pip (not in conda)
RUN micromamba run -n biotools pip install --no-cache-dir doubletdetection || true
```

### 4. scvi-tools not installed
**Problem:** pip installation failed due to PyTorch dependencies
**Fix:** Install via conda with pytorch
```dockerfile
# Before
RUN micromamba run -n biotools pip install --no-cache-dir \
    scvi-tools \
    || true

# After
RUN micromamba install -n biotools -c conda-forge -c bioconda -y \
    pytorch scvi-tools \
    && micromamba clean --all -y || true
```

### 5. squidpy/scvelo not installed
**Problem:** pip installation failed
**Fix:** Use conda
```dockerfile
# Before
RUN micromamba run -n biotools pip install --no-cache-dir \
    squidpy \
    || true

RUN micromamba run -n biotools pip install --no-cache-dir \
    scvelo \
    || true

# After
RUN micromamba install -n biotools -c conda-forge -c bioconda -y \
    squidpy scvelo \
    && micromamba clean --all -y || true
```

---

## Key Lessons Learned

1. **Prefer conda over pip** for bioinformatics packages - better dependency resolution
2. **Pin versions** when known compatibility issues exist (e.g., pandas<2.0 for cnvkit)
3. **Use bioconductor-* packages** via conda instead of BiocManager for R packages
4. **Add explicit dependencies** when tools require shared libraries (e.g., hdf5 for kallisto)
5. **Specify Java version** for Java-based tools to avoid LinkageErrors
6. **Add Perl modules** explicitly for Perl-based tools like VEP

---

## Verification

After rebuilding, run verification scripts:
```bash
docker run --platform linux/amd64 biomate/wgs-wes:x86
docker run --platform linux/amd64 biomate/rnaseq:x86
docker run --platform linux/amd64 biomate/cutandrun:x86
docker run --platform linux/amd64 biomate/singlecell:x86
```
