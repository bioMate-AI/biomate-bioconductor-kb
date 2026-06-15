---
name: bioconductor-immunotation
description: MHC (major histocompatibility complex) molecules are cell surface complexes that present antigens to T cells.  The repertoire of antigens presented in a given genetic background largely depends on the sequence of the encoded MHC molecules, and thus, in humans, on the highly variable HLA (human leukocyte antigen) genes of the hyperpolymorphic HLA locus. More than 28,000 different HLA alleles have been reported, with significant differences in allele frequencies between human populations worldwide
when_to_use: Use when: MHC (major histocompatibility complex) molecules are cell surface complexes that present antigens to T cells; User guide immunotation. Not for: Requires R ≥ 4.1 and Bioconductor ≥ 3.16
user-invocable: false
---

# immunotation

## Workflows

### Standard Workflow

```r
library(immunotation)

# 1. Retrieve valid organisms and chain lookup table for humans
organisms <- get_valid_organisms()
human_chains <- retrieve_chain_lookup_table(organism = "human")

# 2. Map HLA alleles to serotypes and NetMHCpan inputs
allele_list <- c("A*01:01:01", "A*02:01:01", "B*39:01:01")
serotypes <- get_serotypes(allele_list, mhc_type = "MHC-I")
mhcpan_input <- get_mhcpan_input(allele_list, mhc_class = "MHC-I")

# 3. Query allele frequencies in global populations
freq_data <- query_allele_frequencies(
  hla_selection = "A*02:01", 
  hla_sample_size_pattern = "bigger_than", 
  hla_sample_size = 10000, 
  standard = "g"
)
```
**Input/Output Note:** Inputs are HLA allele lists and population query parameters; outputs are serotypes, tool-compatible HLA strings, and population frequency tables.

## When to Use
- Converting HLA allele names to serotypes using `get_serotypes`.
- Formatting HLA alleles for immunoinformatics tools like NetMHCpan using `get_mhcpan_input`.
- Mapping HLA alleles to G groups (`get_G_group`) or P groups (`get_P_group`).
- Querying HLA allele and haplotype frequencies from the Allele Frequency Net Database (AFND) using `query_allele_frequencies` and `query_haplotype_frequencies`.
- Visualizing global allele frequency distributions on a world map using `plot_allele_frequency`.

## When NOT to Use
- For predicting peptide-MHC binding directly (use tools like NetMHCpan; `immunotation` only formats the inputs).
- For non-MHC/HLA gene annotations.

## Data Requirements
- Character vectors of HLA allele names in standard WHO nomenclature (e.g., `"A*01:01:01"`).

## Key Parameters
- **organism**: Species name (e.g., `"human"`, `"mouse"`) used in `retrieve_chain_lookup_table`.
- **mhc_type**: MHC class type (`"MHC-I"` or `"MHC-II"`) used in `get_serotypes`.
- **mhc_class**: MHC class (`"MHC-I"` or `"MHC-II"`) used in `get_mhcpan_input`.
- **hla_selection**: HLA allele or allele group to query.
- **hla_sample_size_pattern**: Pattern for filtering sample size (e.g., `"bigger_than"`).
- **hla_sample_size**: Minimum sample size for population queries.
- **standard**: AFND data standard quality filter (e.g., `"g"` for Gold, `"s"` for Silver, `"b"` for Bronze).

## Best Practices
- Use `get_valid_organisms` to check if a species is supported before building a lookup table.
- Convert alleles to G or P groups using `get_G_group` or `get_P_group` to resolve ambiguous HLA typings.
- Filter AFND queries using `standard = "g"` (Gold standard) to ensure high-quality allele frequency data.

## Common Pitfalls
- Querying MHC-II serotypes with incomplete alpha/beta chain annotations, which returns `NA`. Ensure both chains are annotated in the MHC restriction ontology (MRO).

## Alternatives
- `HLAtools`: For general HLA data manipulation and analysis.

## Citations
- Robinson J, Barker DJ, Georgiou X et al. IPD-IMGT/HLA Database. Nucleic Acids Research (2020)
- Gonzalez-Galarza FF, McCabe A, Santos EJ at al. Allele frequency net database (AFND) 2020 update. Nucleic Acids Research (2020)

## References
- Homepage: bioconductor.org/packages/immunotation
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/immunotation/inst/doc/immunotation.html
