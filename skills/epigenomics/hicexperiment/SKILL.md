---
name: bioconductor-hicexperiment
description: R generic interface to Hi-C contact matrices in `.(m)cool`, `.hic` or HiC-Pro derived formats, as well as other Hi-C processed file formats. Contact matrices can be partially parsed using a random access method, allowing a memory-efficient representation of Hi-C data in R. The `HiCExperiment` class stores the Hi-C contacts parsed from local contact matrix files. `HiCExperiment` instances can be further investigated in R using the `HiContacts` analysis package.
when_to_use: Use when: R generic interface to Hi-C contact matrices in `.(m)cool`, `.hic` or HiC-Pro derived formats, as well as other Hi-C pro; opts using suppressPackageStartupMessages; load lib using showClass, contacts_yeast; graph using include_graphics; evaled import using HiContactsData, import; many imports using HiContactsData, CoolFile. Not for: Requires R ≥ 4.2 and Bioconductor ≥ 3.16
user-invocable: false
---

# HiCExperiment

## Workflows

### Standard Workflow

```r
library(HiCExperiment)
library(HiContactsData)

# Retrieve a sample cool file path
cool_file <- HiContactsData('yeast_wt', format = 'cool')

# Import the contact matrix as a HiCExperiment object
hic <- import(cool_file, format = 'cool', focus = 'I:20001-80000')

# Inspect the imported object
resolution(hic)
```
Input: A path to a `.cool`, `.mcool`, `.hic`, or HiC-Pro contact matrix file.
Output: A parsed `HiCExperiment` object containing contact frequencies, genomic bins, and metadata.

## When to Use
- Importing Hi-C contact matrices stored in `.cool`, `.mcool`, `.hic`, or HiC-Pro formats using `import()`.
- Performing memory-efficient random access or subsetting of genomic loci during import using the `focus` argument.
- Coercing Hi-C experiment data into standard Bioconductor structures like `GInteractions`, `ContactMatrix`, or base `matrix` using `as()`.

## When NOT to Use
- For downstream Hi-C analysis tasks like compartment calling or insulation score calculation, use `HiContacts` instead of `HiCExperiment` alone.
- For subsetting HiC-Pro formatted matrices during import, as `HiCExperiment` does not support the `focus` argument for HiC-Pro files (they must be fully imported into memory).

## Data Requirements
- Input files must be in `.cool`, `.mcool`, `.hic`, or HiC-Pro format (which consists of a `.matrix` and a `.bed` file).
- Optional `.pairs` or `.pairs.gz` files can be linked using `CoolFile()`, `HicFile()`, or `HicproFile()` via the `pairsFile` argument.

## Key Parameters
- **format** (NULL): Specifies the file format to import (e.g., `'cool'`, `'pairs'`).
- **focus** (NULL): A character string (e.g., `'I:20001-80000'` or `'II:1-500000|II:100001-300000'`) to subset contacts within a genomic locus of interest.
- **resolution** (NULL): Numeric value specifying the resolution at which count values are recovered from multi-resolution files.
- **pairsFile** (NULL): Path to a pairs file containing chimeric pairs to associate with the contact matrix.

## Best Practices
- Query available resolutions in multi-resolution files using `availableResolutions()` before importing.
- Check available chromosomes in a file using `availableChromosomes()` to construct valid `focus` queries.
- Retrieve the genomic binning structure at the active resolution using `bins()` or unique regions using `regions()`.

## Common Pitfalls
- Attempting to query subsets of HiC-Pro formatted matrices using `focus`: This is unsupported and will cause the entire matrix to be imported into memory.
- Accessing missing scores (e.g., normalized/balanced scores) when they are not present in the input file: Verify available scores using `scores(hic)` first.

## Alternatives
- `InteractionSet`: For general representation of genomic interactions without specialized Hi-C file parsers.

## Citations
- Lun, Perry & Ing-Simmons, F1000 Research 2016 (for base Bioconductor classes GInteractions and ContactMatrix).

## References
- Homepage: bioconductor.org/packages/HiCExperiment
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/HiCExperiment/inst/doc/HiCExperiment.html
