---
name: bioconductor-faers
description: The FDA Adverse Event Reporting System (FAERS) is a database used for the spontaneous reporting of adverse events and medication errors related to human drugs and therapeutic biological products. faers pacakge serves as the interface between the FAERS database and R. Furthermore, faers pacakge offers a standardized approach for performing pharmacovigilance analysis.
when_to_use: Use when: The FDA Adverse Event Reporting System (FAERS) is a database used for the spontaneous reporting of adverse events and me; FAERS-Pharmacovigilance. Not for: Requires R ≥ 3.5.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# faers

## Workflows

### Standard Workflow

```r
library(faers)

# 1. Check metadata of FAERS
faers_meta(internal = TRUE)

# 2. Download and parse quarterly data files
data2 <- faers(
  c(2004, 2017), 
  c("q1", "q2"), 
  dir = system.file("extdata", package = "faers"), 
  compress_dir = tempdir()
)

# 3. Retrieve specific field data (e.g., demographic data)
demo_data <- faers_get(data2, "demo")

# 4. Load standardized data and retrieve MedDRA hierarchy
data_std <- readRDS(system.file("extdata", "standardized_data.rds", package = "faers"))
meddra_hier <- faers_meddra(data_std, use = "hierarchy")
```
**Input/Output Note:** Inputs are year, quarter, and directory paths for FAERS raw data; outputs are standardized FAERS data tables and MedDRA hierarchy mappings.

## When to Use
- Accessing and parsing the FDA Adverse Event Reporting System (FAERS) quarterly data files.
- Retrieving specific demographic, drug, or reaction fields using `faers_get`.
- Standardizing drug and reaction terms to MedDRA terminology using `faers_standardize` and `faers_meddra`.

## When NOT to Use
- For analyzing clinical trial adverse events that are not part of the FAERS public database.
- For real-time adverse event tracking (FAERS data is released quarterly).

## Data Requirements
- Raw FAERS quarterly data files (ASCII or XML format).
- MedDRA terminology files for standardization.

## Key Parameters
- **internal** (`FALSE`): Logical indicating whether to use internal cached FAERS metadata in `faers_meta`.
- **dir**: Directory path where FAERS data files are stored or downloaded.
- **compress_dir**: Temporary directory for uncompressing downloaded files.
- **use** (`"hierarchy"`): Component of MedDRA to retrieve (e.g., `"hierarchy"` or `"SMQ"`).

## Best Practices
- Check FAERS metadata using `faers_meta(internal = TRUE)` to verify available quarters and file sizes before downloading.
- Use `faers_combine` to merge multiple quarters of parsed FAERS data into a single object.
- Standardize drug and reaction terms using `faers_standardize` with a valid MedDRA path to ensure consistent terminology.

## Common Pitfalls
- Attempting to run standardization without providing a valid path to uncompressed MedDRA data. Ensure `meddra_path` is correctly specified.

## Alternatives
- `openfda`: For querying the OpenFDA API directly instead of parsing raw quarterly files.

## Citations
- FDA Adverse Event Reporting System (FAERS) documentation.

## References
- Homepage: bioconductor.org/packages/faers
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/faers/inst/doc/FAERS-Pharmacovigilance.html
