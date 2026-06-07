---
name: bioconductor-mzr
description: mzR provides a unified API to the common file formats and parsers available for mass spectrometry data. It comes with a subset of the proteowizard library for mzXML, mzML and mzIdentML. The netCDF reading code has previously been used in XC
when_to_use: Use when: Low-Level Raw Data Access: High-performance reading of raw mass spectrometry data formats (mzML, mzXML, netCDF) using openMSfile().; Metadata Extraction: Accessing metadata, instrument configurations, run summaries, and individual scan headers from raw MS files using runInfo(), instrumentInfo(), and header().; Spectral Extraction: Extracting raw mass spectra (m/z and intensity arrays) using the pe. Not for: For high-level, user-friendly mass spectrometry data manipulation and processing, use MSnbase instead because mzR is strictly a low-level data access API.; For high-level metabolomics preprocessing (peak picking, alignment), use xcms instead because 
user-invocable: false
---

# mzR

## When to Use
- **Low-Level Raw Data Access**: High-performance reading of raw mass spectrometry data formats (mzML, mzXML, netCDF) using `openMSfile()`.
- **Metadata Extraction**: Accessing metadata, instrument configurations, run summaries, and individual scan headers from raw MS files using `runInfo()`, `instrumentInfo()`, and `header()`.
- **Spectral Extraction**: Extracting raw mass spectra (m/z and intensity arrays) using the `peaks()` function.
- **Fast ID Parsing**: Reading mzIdentML (.mzid) files rapidly using the C++ ProteoWizard parser backend via `openIDfile()`.

## When NOT to Use
- For high-level, user-friendly mass spectrometry data manipulation and processing, use `MSnbase` instead because `mzR` is strictly a low-level data access API.
- For high-level metabolomics preprocessing (peak picking, alignment), use `xcms` instead because `mzR` does not provide these algorithms natively.

## Data Requirements
- **Input**: Raw mass spectrometry files in standard open formats: `.mzML`, `.mzXML`, `.cdf` (netCDF), or `.mzid` (for identifications).

## Key Parameters
- **filename**: Path to the raw mass spectrometry or identification file passed to `openMSfile()` or `openIDfile()`.

## Best Practices
- **Close File Connections**: Always close the file connection using `close()` when not needed anymore to release the memory of cached content.
- **Header-First Inspection**: Use `header()` to retrieve a summary of all scans (retention time, MS level, precursor m/z) before loading heavy raw spectral arrays with `peaks()`.
- **Check Peak Counts**: Use `peaksCount()` to determine the number of peaks in a spectrum before extracting the full m/z and intensity matrices.

## Common Pitfalls
- **Memory Leaks**: Forgetting to close file handles after extracting data, leading to exhausted memory. *Fix*: Always call `close()` on the opened file object when finished.
- **Direct Usage for Complex Workflows**: Attempting to build complex processing pipelines directly on top of `mzR` pointers. *Fix*: Use `MSnbase` (with on-disk mode) which uses `mzR` internally but offers a coherent, high-level S4 interface.

## Alternatives
- **MSnbase**: For a comprehensive, high-level container handling both raw spectra and metadata, supporting reading multiple files at once.
- **xcms**: For comprehensive metabolomics preprocessing pipelines (peak alignment, matching, and identification).

## Citations
- Chambers M, Maclean B, Burke R, Amodei D, Ruderman DL, Neumann S, Gatto L, Mallick P (2012). "A cross-platform toolkit for mass spectrometry and proteomics." *Nature Biotechnology*, 30(10), 918-920.
- Kessner D, Chambers M, Burke R, Agus D, Mallick P (2008). "ProteoWizard: Open Source Software for Rapid Proteomics Tools Development." *Bioinformatics*, 24(21), 2534-2536.

## References
- Homepage: https://bioconductor.org/packages/mzR
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/mzR/inst/doc/mzR.html
