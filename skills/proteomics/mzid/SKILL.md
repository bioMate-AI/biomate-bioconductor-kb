---
name: bioconductor-mzid
description: A parser for mzIdentML files implemented using the XML package. The parser tries to be general and able to handle all types of mzIdentML files with the drawback of having less 'pretty' output than a vendor specific parser. Please contact th
when_to_use: Use when: Parsing mzIdentML Files: Reading HUPO-PSI standard mzIdentML (.mzid) files containing peptide and protein identification results using the mzID() function.; Data Flattening: Converting complex, nested structures of mzIdentML files into flat, easy-to-manipulate R data.frame objects using the flatten() function.; Metadata Extraction: Extracting search database details, peptide-spectrum matches (PSMs. Not for: For parsing raw mass spectrometry spectra (mzML, mzXML) or quantitative data (mzQuantML), use mzR instead because mzID only parses identification files.; For high-level quantitative proteomics data manipulation, use MSnbase instead because mzID is st
user-invocable: false
---

# mzID

## When to Use
- **Parsing mzIdentML Files**: Reading HUPO-PSI standard `mzIdentML` (.mzid) files containing peptide and protein identification results using the `mzID()` function.
- **Data Flattening**: Converting complex, nested structures of mzIdentML files into flat, easy-to-manipulate R `data.frame` objects using the `flatten()` function.
- **Metadata Extraction**: Extracting search database details, peptide-spectrum matches (PSMs), and search engine scores for downstream custom analysis.

## When NOT to Use
- For parsing raw mass spectrometry spectra (mzML, mzXML) or quantitative data (mzQuantML), use `mzR` instead because `mzID` only parses identification files.
- For high-level quantitative proteomics data manipulation, use `MSnbase` instead because `mzID` is strictly a barebones parser for identification data.

## Data Requirements
- **Input**: Valid `mzIdentML` (.mzid) files conforming to the HUPO-PSI schema.
- **Structure**: The parsed `mzID` object contains slots for `parameters`, `psm`, `peptides`, `evidence`, and `database`.

## Key Parameters
- **file**: Path to the mzIdentML file to be parsed (passed as the first argument to `mzID()`).

## Best Practices
- **Flatten Immediately**: Use the `flatten()` function immediately after parsing to convert the complex S4 `mzID` object into a flat `data.frame` for standard R operations.
- **Inspect Column Meanings**: Carefully inspect the column names of the flattened results (e.g., using `names()`), as ambiguity can arise (e.g., `length` refers to the nucleotide sequence coding for the protein, not the peptide length).
- **Verify Sequence Lengths**: Use `nchar()` and `substr()` on the sequence columns to verify you are working with the expected string lengths.

## Common Pitfalls
- **Misinterpreting Flattened Columns**: Assuming the `length` column in a flattened `data.frame` refers to the peptide sequence length. *Fix*: Inspect the content using `flatResults$length` and verify it refers to the protein's nucleotide sequence length.
- **Parsing Errors on Custom Files**: Encountering errors during parsing due to the multitude of different ways software writes mzIdentML files. *Fix*: Contact the package maintainer to get the specific file structure supported.

## Alternatives
- **mzR**: For fast, C++-based parsing of mzIdentML files using the ProteoWizard backend, as well as raw mzXML/mzML files.
- **MSnbase**: For reading and managing both identification and quantitation data in unified, high-level containers.

## Citations
- Pedersen TL (2026). *Parsing mzIdentML files using mzID*. R package vignette.

## References
- Homepage: https://bioconductor.org/packages/mzID
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/mzID/inst/doc/mzID.html
