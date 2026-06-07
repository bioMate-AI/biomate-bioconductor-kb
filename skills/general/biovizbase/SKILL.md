---
name: bioconductor-biovizbase
description: The biovizBase package is designed to provide a set of utilities, color schemes and conventions for genomic data. It serves as the base for various high-level packages for biological data visualization. This saves development effort and enc
when_to_use: Use when: Generating colorblind-safe palettes for biological data visualization using colorBlindSafePal().; Retrieving standardized, biologically sensible color schemes for cytobands, strands, or nucleotides using getBioColor().; Manipulating GRanges objects for plotting by adding disjoint stepping levels (addStepping()) or shrinking gaps (shrinkageFun()).; Fetching chromosome ideograms from the UCSC genome. Not for: For high-level, out-of-the-box static genomic plotting, use ggbio because biovizBase only provides the low-level utilities and color schemes.; For interactive genomic graphics, use visnab because biovizBase is designed as a foundational infrastructur
user-invocable: false
---

# biovizBase

## When to Use
- Generating colorblind-safe palettes for biological data visualization using `colorBlindSafePal()`.
- Retrieving standardized, biologically sensible color schemes for cytobands, strands, or nucleotides using `getBioColor()`.
- Manipulating `GRanges` objects for plotting by adding disjoint stepping levels (`addStepping()`) or shrinking gaps (`shrinkageFun()`).
- Fetching chromosome ideograms from the UCSC genome browser using `getIdeogram()`.

## When NOT to Use
- For high-level, out-of-the-box static genomic plotting, use `ggbio` because `biovizBase` only provides the low-level utilities and color schemes.
- For interactive genomic graphics, use `visnab` because `biovizBase` is designed as a foundational infrastructure package rather than an interactive plotting tool.

## Data Requirements
- **Input Format**: `GRanges` objects (from the `GenomicRanges` package) for genomic manipulations, or character vectors of biological categories (e.g., "A", "C", "T", "G", "N") for color mapping.
- **Structure**: Genomic coordinates must be properly formatted in `GRanges` to use utilities like `addStepping()`, `maxGap()`, or `gaps()`.

## Key Parameters
- **repeatable** (TRUE): Controls whether to repeat colors if the required number exceeds the maximum colors allowed in `colorBlindSafePal()`.
- **source** ("default"): Specifies whether to retrieve colors from the default fixed settings or from the user's options in `getBioColor()`.
- **extend.size** (5): The size to extend ranges when adding stepping levels in `addStepping()`.
- **max.gap** (0): The maximum gap size allowed when shrinking gaps using `shrinkageFun()`.
- **cytoband** (TRUE): Logical indicating whether to include cytoband information when fetching an ideogram with `getIdeogram()`.

## Best Practices
- Use `getBioColor()` instead of accessing options directly to hide internal complexity and ensure uniform color schemes across all graphics.
- Check custom color palettes for colorblind safety using `dichromat()` to ensure accessibility for deuteranopia and protanopia.
- Use `plotColorLegend()` or `showColor()` to visually verify your selected color schemes before applying them to complex genomic plots.

## Common Pitfalls
- **Running out of colors in a palette**: Requesting more colors than a specific colorblind-safe palette supports returns `NA` or errors. Fix: Set `repeatable = TRUE` when calling the function returned by `colorBlindSafePal()`.
- **Inconsistent color themes across plots**: Hardcoding colors leads to mismatched figures. Fix: Temporarily edit colors in the global options (`options(biovizBase = opts)`) so `getBioColor()` returns uniform colors globally.

## Alternatives
- `ggbio`: Built on top of `biovizBase`, use this for actual static genomic plotting rather than just base utilities.
- `visnab`: Built on top of `biovizBase`, use this for interactive genomic graphics.
- `RColorBrewer`: Provides general color palettes, but lacks the built-in biological category mappings (like nucleotides or cytobands) provided by `biovizBase`.
- `dichromat`: Used for colorblindness simulation, but does not provide genomic-specific color generators out of the box.

## Citations
- Tengfei Yin, Michael Lawrence, Dianne Cook (2026). "An Introduction to biovizBase".

## References
- Homepage: https://bioconductor.org/packages/biovizBase
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/biovizBase/inst/doc/biovizBase.pdf
