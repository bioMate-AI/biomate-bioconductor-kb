---
name: bioconductor-seqlogo
description: seqLogo takes the position weight matrix of a DNA sequence motif and plots the corresponding sequence logo as introduced by Schneider and Stephens (1990).
when_to_use: Use when: Visualizing sequence logos for DNA sequence alignments using seqLogo().; Representing position weight matrices (PWM) and their information content profiles using makePWM().; Plotting RNA sequence logos by specifying the RNA alphabet and custom fill colors.. Not for: For highly customized ggplot2-based sequence logos, use ggseqlogo instead because seqLogo uses the base grid package for rendering.; For protein/amino acid sequence logos, use ggseqlogo instead because seqLogo is currently implemented primarily for D
user-invocable: false
---

# seqLogo

## When to Use
- Visualizing sequence logos for DNA sequence alignments using `seqLogo()`.
- Representing position weight matrices (PWM) and their information content profiles using `makePWM()`.
- Plotting RNA sequence logos by specifying the RNA alphabet and custom fill colors.

## When NOT to Use
- For highly customized ggplot2-based sequence logos, use `ggseqlogo` instead because `seqLogo` uses the base `grid` package for rendering.
- For protein/amino acid sequence logos, use `ggseqlogo` instead because `seqLogo` is currently implemented primarily for DNA/RNA sequences.

## Data Requirements
- A simple `matrix` or `data.frame` where column probabilities add up to 1.0.
- An instance of the `pwm` class created by `makePWM()`.

## Key Parameters
- **pwm**: The position weight matrix for which the sequence logo is to be plotted (can be a `pwm` object, `matrix`, or `data.frame`).
- **ic.scale**: Logical indicating whether the height of each column is to be proportional to its information content.
- **fill**: A named character vector to change the default colors for the nucleotides (e.g., A, C, G, T or U).
- **alphabet**: Character string to specify the alphabet, such as "RNA" for RNA logos.

## Best Practices
- Construct a `pwm` object from a matrix or data frame using `makePWM()` to automatically check that column probabilities sum to 1.0.
- Use `ic.scale=FALSE` if you want all columns to have the same uniform height rather than being scaled by information content.
- When plotting RNA logos, specify `alphabet="RNA"` in `makePWM()` and provide fill colors for either c("A", "C", "G", "U") or c("A", "C", "G", "T").

## Common Pitfalls
- **Unnormalized Matrix**: Column probabilities do not sum to 1.0. *Fix*: Ensure the input `matrix` or `data.frame` is properly normalized before passing it to `makePWM()`.
- **Incorrect color mapping for RNA logos**: The default colors may not map correctly to Uracil. *Fix*: Provide a named character vector to the `fill` argument in `seqLogo()` with specific colors for A, C, G, and T/U.
- **Attempting to plot amino acid sequences**: The package will fail or produce incorrect logos. *Fix*: Use a different package, as the vignette notes `seqLogo` is designed for DNA/RNA alignments.

## Alternatives
- **ggseqlogo**: Uses ggplot2 for rendering, allowing for more modern and flexible plot customization.
- **universalmotif**: Provides comprehensive motif manipulation and visualization for various alphabets.
- **motifStack**: Allows plotting stacked logos and tree-structured logos for multiple motifs.

## Citations
- Schneider, Thomas D., and R.Michael Stephens. 1990. "Sequence logos: a new way to display consensus sequences." Nucleic Acids Research 18 (20): 6097-6100.
- Schneider, Thomas D., Gary D. Stormo, Larry Gold, and Andrzej Ehrenfeucht. 1986. "Information Content of Binding Sites on Nucleotide Sequences." Journal of Molecular Biology 188 (3): 415-31.

## References
- Homepage: https://bioconductor.org/packages/seqLogo
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/seqLogo/inst/doc/seqLogo.pdf
