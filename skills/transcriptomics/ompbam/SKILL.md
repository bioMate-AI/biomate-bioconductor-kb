---
name: bioconductor-ompbam
description: This packages provides C++ header files for developers wishing to create R packages that processes BAM files. ompBAM automates file access, memory management, and handling of multiple threads 'behind the scenes', so developers can focus on creating domain-specific functionality. The included vignette contains detailed documentation of this API, including quick-start instructions to create a new ompBAM-based package, and step-by-step explanation of the functionality behind the example packaged in
when_to_use: Use when: This packages provides C++ header files for developers wishing to create R packages that processes BAM files; ompBAM API Documentation; Single-cell RNA-seq analysis (ompBAM). Not for: Requires R ≥ 4.0.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# ompBAM

## Workflows

### Standard Workflow

```r
library(ompBAM)

# Create a new package template that compiles with ompBAM
pkg_path <- file.path(tempdir(), "MyPkg")
use_ompBAM(pkg_path)

# Retrieve the path to an example BAM file provided by the package
bam_path <- ompBAM::example_BAM("Unsorted")
```
*Input:* A destination directory path for the new package.  
*Output:* A fully configured R package directory structure containing C++ templates and configuration files linked to `ompBAM`.

## When to Use
- Developing R packages that require high-performance, multi-threaded processing of BAM files using C++ and OpenMP.
- Writing custom BAM parsing algorithms where you want `ompBAM` to handle file access, BGZF decompression, and thread management.
- Creating packages that need to run on unsorted and unindexed BAM files (e.g., using `pbam_in` and `pbam1_t` APIs).

## When NOT to Use
- For standard BAM manipulation or filtering in R without writing C++ code; use `Rsamtools` or `GenomicAlignments` instead.
- For querying small genomic regions of sorted and indexed BAM files; use `htslib` directly as `ompBAM` is optimized for whole-file sequential reads.

## Data Requirements
- Input BAM files (can be unsorted and unindexed).
- A package development environment with `Rcpp` and a C++ compiler supporting OpenMP (e.g., `gcc` or `clang` with OpenMP libraries).

## Key Parameters
- **path** (in `use_ompBAM`): The directory path where the new package project will be created.
- **bam_file**: Path to the BAM file to be processed.
- **n_threads**: Number of threads to use for parallel execution.

## Best Practices
- Run `devtools::document()` on the newly created package to generate the `NAMESPACE` and export the R wrapper functions.
- Use the `#ifdef _OPENMP` directive in C++ code to ensure compatibility with systems that do not have OpenMP installed (such as default macOS configurations).
- Call `pbam1_t::realize()` if you need to store reads in memory across multiple calls of `pbam_in::fillReads()`, as virtual reads point to temporary buffers.

## Common Pitfalls
- **macOS Compilation Failure**: macOS does not support OpenMP natively. Fix: Install `libomp` via Homebrew (`brew install libomp`) and configure compiler flags.
- **Memory Corruption with Virtual Reads**: Accessing `pbam1_t` objects after calling `fillReads()` leads to segmentation faults. Fix: Call `realize()` on the `pbam1_t` object to copy the data into persistent memory.
- **Requesting Too Many Threads**: Requesting more threads than available can degrade performance. Fix: Use a helper function to cap requested threads at `omp_get_max_threads()`.

## Alternatives
- **Rsamtools**: For high-level BAM file manipulation and querying in R.
- **GenomicAlignments**: For representing and manipulating genomic alignments in R.
- **Rcpp**: For general C++ integration in R packages without built-in BAM parsing support.

## Citations
- Alex C H Wong (2026). ompBAM API Documentation.

## References
- Homepage: https://bioconductor.org/packages/ompbam
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/ompbam/inst/doc/ompBAM-API-Docs.html
