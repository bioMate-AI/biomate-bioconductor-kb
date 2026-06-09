---
name: bioconductor-flowcore
description: Provides S4 data structures and basic functions to deal with flow cytometry data.
when_to_use: Use when: FCS3.0 Standard Parsing: Reading and interpreting Flow Cytometry Data File Standard Version FCS3.0 files.; Segment Extraction: Locating and extracting HEADER, TEXT, DATA, and ANALYSIS segments from flow cytometry data sets.; Large File Handling: Processing data sets of 100 megabytes and larger where byte offsets exceed standard limits.; Compensation Matrix Retrieval: Extracting the fluorescence co. Not for: Automated Cell Clustering: For automated cell clustering, use flowMeans instead because flowCore focuses on file standard specifications and data structures.; Probability Binning: For generating multivariate probability distribution fingerprints, use
user-invocable: false
---

# flowCore

## When to Use
- **FCS3.0 Standard Parsing**: Reading and interpreting Flow Cytometry Data File Standard Version FCS3.0 files.
- **Segment Extraction**: Locating and extracting HEADER, TEXT, DATA, and ANALYSIS segments from flow cytometry data sets.
- **Large File Handling**: Processing data sets of 100 megabytes and larger where byte offsets exceed standard limits.
- **Compensation Matrix Retrieval**: Extracting the fluorescence compensation matrix ($COMP) applied to the data.

## When NOT to Use
- **Automated Cell Clustering**: For automated cell clustering, use flowMeans instead because flowCore focuses on file standard specifications and data structures.
- **Probability Binning**: For generating multivariate probability distribution fingerprints, use flowFP instead because flowCore only handles the raw file segments.

## Data Requirements
- **Input Format**: FCS3.0 conformant files.
- **Structure**: Must contain HEADER, TEXT, and DATA segments.
- **Storage Mode**: List mode data storage or histograms.

## Key Parameters
- **$BEGINDATA** (required): Byte-offset from the beginning of the data set to the beginning of the DATA segment.
- **$DATATYPE** (required): Type of data in the DATA segment (ASCII 'A', integer 'I', single precision floating point 'F', or double precision 'D').
- **$BYTEORD** (required): Byte order for the data acquisition computer (e.g., 4,3,2,1 or 1,2,3,4).
- **$COMP** (optional): Fluorescence compensation matrix elements stored in row-major order.
- **$PnB** (required): Number of bits reserved for parameter number n.
- **$PnR** (required): Range for parameter number n.

## Best Practices
- **Primary TEXT Segment Placement**: Ensure the primary TEXT segment is located entirely within the first 99,999,999 bytes of the data set.
- **ANALYSIS Segment Verification**: Check the $BEGINANALYSIS and $ENDANALYSIS keywords to determine if an ANALYSIS segment is present, especially if HEADER offsets are zero.
- **Internationalization**: Use the $UNICODE keyword to support multi-byte characters for string type keyword values.
- **Data Integrity**: Utilize the cyclic redundancy check (CRC) word placed at the end of each FCS3.0 data set to confirm file integrity after network transfers.

## Common Pitfalls
- **Large Data Set Offsets**: Data sets exceed the 99,999,999 byte limit, causing standard HEADER offsets to fail. *Fix*: Substitute '0's in the HEADER and place the true byte offsets in the $BEGINDATA and $ENDDATA keyword values in the TEXT segment.
- **Delimiter Collisions**: The delimiter character appears within a keyword or keyword value. *Fix*: Immediately follow the delimiter with a second identical delimiter character to escape it.
- **Missing Zero Values in Free Format ASCII**: Free format ASCII data ($DATATYPE/A/ with $PnB/*/) misinterprets consecutive delimiters. *Fix*: Explicitly specify zero values with the zero (0) character rather than leaving empty space between delimiters.

## Alternatives
- **flowMeans**: For downstream non-parametric clustering of the extracted flow cytometry data.
- **flowFP**: For fingerprinting and probability binning of the extracted flow cytometry data.

## Citations
- Data File Standards Committee of the International Society for Analytical Cytology (ISAC). FCS version 2.18.0 can be found in Cytometry 1990;11(3):323-32.

## References
- Homepage: bioconductor.org/packages/flowcore
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/flowCore/inst/doc/HowTo-flowCore.pdf
