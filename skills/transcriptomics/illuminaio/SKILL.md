---
name: bioconductor-illuminaio
description: Tools for parsing Illumina's microarray output files, including IDAT.
when_to_use: Use when: Raw IDAT parsing: Reading raw binary Illumina IDAT files from expression or genotyping microarrays using readIDAT.; Metadata extraction: Extracting per-bead-type values (e.g., MeanBinData, NumBeadsBinData, DevBinData) directly from Illumina BeadChip platforms.; Custom pipeline building: Providing a mechanism for developers of downstream analysis packages to extract all possible information from ID. Not for: High-level analysis: For end-to-end normalization and differential expression analysis, use downstream packages because illuminaio is strictly designed for raw file parsing and leaves data retention choices to the user.; Affymetrix microarrays: For A
user-invocable: false
---

# illuminaio

## When to Use
- **Raw IDAT parsing**: Reading raw binary Illumina IDAT files from expression or genotyping microarrays using `readIDAT`.
- **Metadata extraction**: Extracting per-bead-type values (e.g., `MeanBinData`, `NumBeadsBinData`, `DevBinData`) directly from Illumina BeadChip platforms.
- **Custom pipeline building**: Providing a mechanism for developers of downstream analysis packages to extract all possible information from IDAT files.

## When NOT to Use
- **High-level analysis**: For end-to-end normalization and differential expression analysis, use downstream packages because `illuminaio` is strictly designed for raw file parsing and leaves data retention choices to the user.
- **Affymetrix microarrays**: For Affymetrix microarray data, use `affy` or `oligo` instead because `illuminaio` is exclusively built for Illumina BeadArray platforms.

## Data Requirements
- **Input format**: Raw Illumina `.idat` files (e.g., `_Grn.idat`).
- **Optional files**: GenomeStudio output files (e.g., tab-separated text files) for comparison and validation.

## Key Parameters
- **file**: Path to the `.idat` file to be parsed by `readIDAT`.

## Best Practices
- Pass the file path directly to `readIDAT`; the function will automatically determine the IDAT format and call the appropriate internal reading routine.
- When comparing `illuminaio` output to GenomeStudio, remember to identify and remove internal control bead-types, as GenomeStudio excludes these automatically.
- Reorder the extracted bead-types numerically if comparing against GenomeStudio output, which sorts bead-types alphabetically.

## Common Pitfalls
- **Discrepancies with GenomeStudio**: Small differences in summarized bead-intensity values when compared to GenomeStudio. *Fix*: Recognize that these are introduced by rounding performed by GenomeStudio that is not carried out by `illuminaio`.
- **Mismatched bead-type counts**: Having more bead-types in the `illuminaio` output than in GenomeStudio exports. *Fix*: Filter out the unannotated internal control bead-types that `illuminaio` extracts by default.

## Alternatives
- **minfi**: High-level package for analyzing Illumina Infinium DNA methylation microarrays that uses `illuminaio` under the hood.
- **beadarray**: Specifically designed for Illumina BeadArray expression data, providing advanced normalization and QC beyond basic parsing.

## Citations
- Mike L Smith, Keith A Baggerly, Henrik Bengtsson, Matthew E Ritchie, and Kasper D Hansen. illuminaio: An open source IDAT parsing tool for Illumina microarrays. *F1000Research*, 2:264, 2013.

## References
- Homepage: https://bioconductor.org/packages/illuminaio
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/illuminaio/inst/doc/Description_of_Encrypted_IDAT_Format.pdf
