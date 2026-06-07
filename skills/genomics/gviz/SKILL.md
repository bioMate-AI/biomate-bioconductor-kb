---
name: bioconductor-gviz
description: Genomic data analyses requires integrated visualization of known genomic information and new experimental data. Gviz uses the biomaRt and the rtracklayer packages to perform live annotation queries to Ensembl and UCSC and translates this to
when_to_use: Use when: Plotting genomic data and annotation features (e.g., CpG islands, gene models) in a genome browser-like layout using plotTracks.; Visualizing run-length encoded numeric vectors or matrices (like NGS read coverage or microarray probes) using DataTrack.; Adding a genomic axis with coordinate tick-marks and directional indicators using GenomeAxisTrack.; Displaying chromosome ideograms fetched from UC. Not for: For purely statistical analysis of genomic data without visualization, use dedicated analysis packages instead because Gviz is strictly a visualization framework.; For interactive, web-based genome browsing, use tools like IGV or UCSC Genome Browser 
user-invocable: false
---

# Gviz

## When to Use
- Plotting genomic data and annotation features (e.g., CpG islands, gene models) in a genome browser-like layout using `plotTracks`.
- Visualizing run-length encoded numeric vectors or matrices (like NGS read coverage or microarray probes) using `DataTrack`.
- Adding a genomic axis with coordinate tick-marks and directional indicators using `GenomeAxisTrack`.
- Displaying chromosome ideograms fetched from UCSC using `IdeogramTrack`.

## When NOT to Use
- For purely statistical analysis of genomic data without visualization, use dedicated analysis packages instead because Gviz is strictly a visualization framework.
- For interactive, web-based genome browsing, use tools like IGV or UCSC Genome Browser instead because Gviz generates static plots via the grid graphics system.

## Data Requirements
- **Genomic features**: Represented as `GRanges`, `IRanges`, or `data.frame` objects.
- **Identifiers**: Valid UCSC genome and chromosome identifiers (e.g., `chr7` on `mm9`) for fetching online annotation data.
- **Sequence information**: A `BSgenome` package (e.g., `BSgenome.Hsapiens.UCSC.hg19`) for `SequenceTrack`.

## Key Parameters
- **from** / **to**: Arbitrary genomic range coordinates to restrict the plotted region in `plotTracks`.
- **extend.left** / **extend.right**: Relative zoom factors or absolute integer values to extend the currently displayed range.
- **type**: The plotting type for numeric data in `DataTrack` (e.g., "histogram", "dot").
- **reverseStrand**: Logical parameter to plot data relative to the opposite (3' -> 5') strand.
- **showId**: Logical scalar to show optional range highlighting annotation in `GenomeAxisTrack`.
- **labelPos**: Controls the arrangement of tick marks (e.g., "alternating", "above", "below").

## Best Practices
- Use `availableDisplayPars` to discover which display parameters control the appearance of a specific track class.
- Register custom display parameter modifications globally using `addScheme` and `options(Gviz.scheme = "myScheme")` to avoid repetitive typing.
- Ensure chromosome names follow the UCSC definition (starting with "chr") when fetching data from online repositories, or disable the check via `options(ucscChromosomeNames=FALSE)`.

## Common Pitfalls
- **Slow plotting or timeouts**: Occurs when fetching large ideogram or annotation data from UCSC; fix this by caching data locally or plotting smaller genomic regions.
- **Overplotting of features**: Occurs when features are too close together for the current device resolution; fix this by zooming in using the `from` and `to` arguments in `plotTracks`.
- **Mixture of forward and reverse strand tracks**: Occurs when combining tracks with different strand orientations; fix this by setting `reverseStrand = TRUE` globally in `plotTracks` rather than per track.

## Alternatives
- `GenomeGraphs`: An older package that Gviz is loosely based on, but Gviz offers increased performance and flexibility.
- `rtracklayer`: Used for importing/exporting genomic annotations and connecting to browsers, but lacks the native R grid graphics plotting capabilities of Gviz.

## Citations
- Hahne F and Ivanek R (2016). Visualizing Genomic Data Using Gviz and Bioconductor. Methods in molecular biology (Clifton, N.J.), 1418, 335-51.

## References
- Homepage: https://bioconductor.org/packages/Gviz
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/Gviz/inst/doc/Gviz.pdf
