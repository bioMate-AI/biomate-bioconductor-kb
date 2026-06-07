---
name: bioconductor-tfbstools
description: TFBSTools is a package for the analysis and manipulation of transcription factor binding sites. It includes matrices conversion between Position Frequency Matirx (PFM), Position Weight Matirx (PWM) and Information Content Matrix (ICM). It c
when_to_use: Use when: Matrix Conversion: Converting Position Frequency Matrices (PFMs) to Position Weight Matrices (PWMs) or Information Content Matrices (ICMs) using toPWM and toICM.; Motif Scanning: Scanning nucleotide sequences or pairwise alignments for transcription factor binding sites using searchSeq or searchAln.; Database Querying: Querying and retrieving matrix data from the JASPAR database using getMatrixSet. Not for: For high-throughput scanning of thousands of large genomic regions, use motifmatchr instead, because searchSeq is optimized for targeted DNAString or DNAStringSet objects rather than massive GRanges peak sets.; For de novo motif discovery without ext
user-invocable: false
---

# TFBSTools

## When to Use
- **Matrix Conversion**: Converting Position Frequency Matrices (PFMs) to Position Weight Matrices (PWMs) or Information Content Matrices (ICMs) using `toPWM` and `toICM`.
- **Motif Scanning**: Scanning nucleotide sequences or pairwise alignments for transcription factor binding sites using `searchSeq` or `searchAln`.
- **Database Querying**: Querying and retrieving matrix data from the JASPAR database using `getMatrixSet`.
- **Random Profile Generation**: Generating random profile matrices via permutation or Dirichlet multinomial mixture models using `permuteMatrix` and `rPWMDmm`.
- **Visualization**: Visualizing sequence logos for basic PWMs or Transcription Factor Flexible Models (TFFMs) using `seqLogo`.

## When NOT to Use
- For high-throughput scanning of thousands of large genomic regions, use `motifmatchr` instead, because `searchSeq` is optimized for targeted `DNAString` or `DNAStringSet` objects rather than massive `GRanges` peak sets.
- For de novo motif discovery without external dependencies, use `universalmotif` because `runMEME` requires the external MEME suite to be installed on the system.

## Data Requirements
- **Input Format**: `PFMatrix` objects, `DNAString` or `DNAStringSet` for sequences, and `Axt` objects for alignments.
- **Structure**: 4-row matrices representing A, C, G, T counts or probabilities.
- **Normalization State**: Raw position frequency counts for PFMs, which are then converted to log2 probability ratios for PWMs.

## Key Parameters
- **type** (default): The type of matrix conversion in `toPWM` (e.g., "log2probratio") or the type of p-value calculation in `pvalues` (e.g., "TFMPvalue").
- **pseudocounts** (default): Numeric value (default 0.8) added to correct small counts or eliminate zero values before log transformation in `toPWM`.
- **bg** (default): A named numeric vector representing background nucleotide frequencies (e.g., `c(A=0.25, C=0.25, G=0.25, T=0.25)`).
- **min.score** (default): Minimum score threshold (e.g., "60%" or "80%") for a sequence match to be reported in `searchSeq` or `searchAln`.
- **schneider** (default): Logical in `toICM` indicating whether to apply the Schneider correction.
- **strand** (default): Controls which strand is searched in `searchSeq` (e.g., "*" for both strands).

## Best Practices
- Use `pseudocounts=0.8` in `toPWM` rather than the square root of sequences to avoid overly harsh corrections on zero values.
- When scanning sequences with `searchSeq`, use `pvalues` with `type="TFMPvalue"` to calculate empirical p-values for the match scores.
- Use `writeGFF3` or `writeGFF2` to export `SiteSet` objects into standard genomic formats for downstream visualization.

## Common Pitfalls
- **Pitfall**: `runMEME` fails to execute.  
  *Fix*: Ensure the external MEME software suite is installed and the `binary` argument correctly points to the executable.
- **Pitfall**: `searchSeq` returns too many false positive hits.  
  *Fix*: Increase the `min.score` threshold (e.g., from "60%" to "90%") to enforce stricter matching.
- **Pitfall**: `toPWM` throws an error due to zero counts.  
  *Fix*: Ensure `pseudocounts` is set to a positive value (like 0.8) to eliminate zero values before log transformation.

## Alternatives
- **motifmatchr**: For faster, parallelized motif scanning across large `GRanges` objects.
- **universalmotif**: For comprehensive motif manipulation and de novo discovery without relying strictly on external binaries like MEME.
- **Biostrings**: For basic PWM matching (`matchPWM`), though it lacks the advanced statistical models and TFFM support of `TFBSTools`.

## Citations
- Tan G, Lenhard B (2016). TFBSTools: an R/Bioconductor package for transcription factor binding site analysis. *Bioinformatics*.
- Mathelier and Wasserman (2013). The next generation of transcription factor binding site, TFFM.

## References
- Homepage: https://bioconductor.org/packages/TFBSTools
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/TFBSTools/inst/doc/TFBSTools.html
