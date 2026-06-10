---
name: bioconductor-psmatch
description: The PSMatch package helps proteomics practitioners to load, handle and manage Peptide Spectrum Matches. It provides functions to model peptide-protein relations as adjacency matrices and connected components, visualise these as graphs and m
when_to_use: Use when: Fragment Ion Calculation: Calculating theoretical MS2 fragment ions (b and y ions) for a peptide sequence using calculateFragments.; Fragment Visualisation: Visualising matched b- and y-ion fragment sequences directly on an MS spectrum using plotSpectraPTM.; Peptide-Protein Modelling: Modelling the relation between peptides and proteins as an adjacency matrix using makeAdjacencyMatrix.; Protein Gr. Not for: For handling and processing raw mass spectrometry spectra, use Spectra because PSMatch relies on it for raw data representation and extraction.; For managing multi-level quantitative proteomics data, use QFeatures because PSMatch focuses on PSM-level
user-invocable: false
---

# PSMatch

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.16.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** S4Vectors, PTMods
- **Imports:** igraph, Spectra, Matrix, BiocParallel, BiocGenerics, ProtGenerics, QFeatures, MsCoreUtils
- **Install:** `BiocManager::install("PSMatch")`

## When to Use
- **Fragment Ion Calculation**: Calculating theoretical MS2 fragment ions (b and y ions) for a peptide sequence using `calculateFragments`.
- **Fragment Visualisation**: Visualising matched b- and y-ion fragment sequences directly on an MS spectrum using `plotSpectraPTM`.
- **Peptide-Protein Modelling**: Modelling the relation between peptides and proteins as an adjacency matrix using `makeAdjacencyMatrix`.
- **Protein Group Resolution**: Partitioning complex peptide-protein graphs into independent subgraphs using `ConnectedComponents` to explore shared and unique peptides.

## When NOT to Use
- For **handling and processing raw mass spectrometry spectra**, use `Spectra` because `PSMatch` relies on it for raw data representation and extraction.
- For **managing multi-level quantitative proteomics data**, use `QFeatures` because `PSMatch` focuses on PSM-level filtering and structural relationships.
- For **applying and managing peptide modifications**, use `PTMods` because `PSMatch` delegates canonical modification handling to it.

## Data Requirements
- **Identification Data**: Imported as a `PSM` object containing columns for peptide sequences (e.g., `"sequence"`) and protein accessions (e.g., `"DatabaseAccess"`).
- **Raw MS Data**: Loaded as a `Spectra` object for fragment ion visualisation.
- **Quantitative Data**: Can be imported as a `SummarizedExperiment` object with protein groups named by peptide sequences.

## Key Parameters
- **addCarbamidomethyl**: Logical in `calculateFragments` and `plotSpectraPTM` to apply carbamidomethylation of cysteines by default.
- **variableModifications**: Named numeric vector in `calculateFragments` or `plotSpectraPTM` to apply variable mass modifications.
- **binary**: Logical in `makeAdjacencyMatrix` to create a binary matrix instead of counting occurrences.
- **protColors**: Numeric or character in `plotAdjacencyMatrix` to control protein node colours based on string distances.
- **pepColors**: Character vector in `plotAdjacencyMatrix` to colour peptide nodes (e.g., by search engine score).
- **split**: Character in `makeAdjacencyMatrix` (e.g., `";"`) to split protein groups into individual proteins.

## Best Practices
- Filter out decoy hits and low-rank matches using `filterPsmDecoy` and `filterPsmRank` before constructing adjacency matrices.
- Merge raw `Spectra` data with `PSM` identification data using `joinSpectraData` to enable fragment visualisation.
- Use `prioritiseConnectedComponents` to rank and identify the most interesting connected components (e.g., those with multiple shared peptides).
- Extract specific subgraphs using `connectedComponents` to manually inspect complex protein groups with `plotAdjacencyMatrix`.

## Common Pitfalls
- **Overlapping fragment ions in visualisations**: Restricted plot windows can cause text to overlap. *Fix*: Run `plotSpectraPTM` locally or adjust the `xlim` parameter in `plotSpectra`.
- **Duplicate keys when merging**: Merging spectra and PSMs can result in duplicates. *Fix*: Be aware that `joinSpectraData` will only keep the last instance if duplicates are found in the key.
- **Missing modifications**: Fragments might not match the spectrum if fixed modifications are ignored. *Fix*: Ensure `addCarbamidomethyl = TRUE` or explicitly pass modifications via `fixedModifications`.

## Alternatives
- **Spectra**: For core MS data infrastructure and raw spectra manipulation.
- **QFeatures**: For downstream quantitative protein-level aggregation and statistical analysis.
- **PTMods**: For defining and retrieving canonical peptide modifications.

## Citations
- Gatto L, Rainer J, Gibb S, Wieczorek S, Burger T, Deflandre G (2026). PSMatch: Handling and Managing Peptide Spectrum Matches. R package.

## References
- Homepage: https://bioconductor.org/packages/PSMatch
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/PSMatch/inst/doc/PSMatch.html
