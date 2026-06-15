---
name: bioconductor-rgoslin
description: The R implementation for the Grammar of Succint Lipid Nomenclature parses different short hand notation dialects for lipid names. It normalizes them to a standard name. It further provides calculated monoisotopic masses and sum formulas for each successfully parsed lipid name and supplements it with LIPID MAPS Category and Class information. Also, the structural level and further structural details about the head group, fatty acyls and functional groups are returned, where applicable.
when_to_use: Use when: Using R Goslin to parse and normalize lipid nomenclature; Metabolomics data analysis (rgoslin); Data normalization and preprocessing (rgoslin). Not for: Requires R ≥ 4.0.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# rgoslin

## Workflows

### Standard Workflow

The R implementation for the Grammar of Succint Lipid Nomenclature parses different shorthand notation dialects for lipid names, normalizes them, and calculates chemical properties.

```r
library(rgoslin)

# Check which grammars are supported
listAvailableGrammars()

# Check whether a given lipid name can be parsed
isValidLipidName("PC 32:1")

# Parse a single lipid name to return a data frame of properties
df <- parseLipidNames("PC 32:1")

# Parse a lipid name with a manually specified grammar
tagDf <- parseLipidNames("TG(16:1(5E)/18:0/20:2(3Z,6Z))", grammar = "LipidMaps")

# Parse multiple lipid names using a vector
multipleLipidNamesDf <- parseLipidNames(c("PC 32:1", "LPC 34:1", "TG(18:1_18:0_16:1)"))
```
*Input: A character vector of lipid shorthand names. Output: A data frame containing parsed lipid properties (e.g., normalized name, mass, sum formula, category).*

## When to Use
- Parsing shorthand lipid names into structural representations using `parseLipidNames()`.
- Validating if a lipid name is compliant with supported grammars using `isValidLipidName()`.
- Retrieving calculated monoisotopic masses, sum formulas, and LIPID MAPS categories for parsed lipids.
- Converting IUPAC-compliant fatty acid names to updated shorthand nomenclature using `parseLipidNames(..., grammar = "FattyAcids")`.

## When NOT to Use
- For general mass spectrometry raw data processing or peak picking; use `xcms` instead.
- For handling raw MSn spectra or chromatograms; use `MSnbase` or `Spectra` instead.

## Data Requirements
- Input data must be a character vector of lipid names (e.g., `"PC 32:1"`, `"TG(16:1(5E)/18:0/20:2(3Z,6Z))"`).
- Supported grammars include `"Shorthand2020"`, `"Goslin"`, `"FattyAcids"`, `"LipidMaps"`, `"SwissLipids"`, and `"HMDB"`.

## Key Parameters
- **grammar** (NULL): The specific grammar to parse against (e.g., `"Goslin"`, `"LipidMaps"`, `"FattyAcids"`). If omitted, all available parsers are tested sequentially.

## Best Practices
- Use `listAvailableGrammars()` to check supported grammars before parsing.
- Explicitly specify the `grammar` parameter in `parseLipidNames()` when parsing large vectors to avoid testing all parsers and improve performance.
- Use `isValidLipidName()` to quickly filter out unparseable names before running full parsing.

## Common Pitfalls
- Omitting the `grammar` argument on large datasets: Causes slow execution because all grammars are tested sequentially. Fix: Specify `grammar = "Goslin"` or another specific grammar.
- Parsing names with unsupported suffixes (like isotopic labels like `(d9)`): Causes parsing errors. Fix: Preprocess names using string manipulation (e.g., `str_match` or `str_replace_all`) to remove or convert suffixes before parsing.

## Alternatives
- `lipidr`: For downstream analysis, visualization, and QC of lipidomics data (can be integrated with `rgoslin`).
- `MSnbase`: For low-level mass spectrometry data container handling.
- `Spectra`: For raw mass spectra representation and processing.

## Citations
- Liebisch et al. 2020, Journal of Lipid Research (for shorthand nomenclature updates).

## References
- Homepage: bioconductor.org/packages/rgoslin
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/rgoslin/inst/doc/introduction.html
