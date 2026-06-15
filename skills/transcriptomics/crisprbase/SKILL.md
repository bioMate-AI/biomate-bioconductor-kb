---
name: bioconductor-crisprbase
description: Provides S4 classes for general nucleases, CRISPR nucleases, CRISPR nickases, and base editors.Several CRISPR-specific genome arithmetic functions are implemented to help extract genomic coordinates of spacer and protospacer sequences. Commonly-used CRISPR nuclease objects are provided that can be readily used in other packages. Both DNA- and RNA-targeting nucleases are supported.
when_to_use: Use when: Provides S4 classes for general nucleases, CRISPR nucleases, CRISPR nickases, and base editors.Several CRISPR-specific g; Introduction to crisprBase. Not for: Requires R ≥ 4.1 and Bioconductor ≥ 3.16
user-invocable: false
---

# crisprBase

## Workflows

### Standard Workflow

Define and manipulate S4 classes representing restriction enzymes, CRISPR nucleases, base editors, and nickases.

```r
library(crisprBase)

# 1. Define SpCas9 Nuclease (3' PAM)
SpCas9 <- CrisprNuclease(
  "SpCas9", 
  targetType = "DNA",
  pams = c("(3/3)NGG", "(3/3)NAG", "(3/3)NGA"),
  weights = c(1, 0.2593, 0.0694),
  pam_side = "3prime", 
  spacer_length = 20
)

# 2. Define AsCas12a Nuclease (5' PAM)
AsCas12a <- CrisprNuclease(
  "AsCas12a", 
  targetType = "DNA",
  pams = "TTTV(18/23)",
  pam_side = "5prime", 
  spacer_length = 23
)

# 3. Define a Cytosine Base Editor (BE4max) with custom editing weights
weightsFile <- system.file("be/b4max.csv", package = "crisprBase", mustWork = TRUE)
ws <- t(read.csv(weightsFile))
ws <- as.data.frame(ws)
colnames(ws) <- ws["Position", ]
ws <- ws[-c(match("Position", rownames(ws))), , drop = FALSE]
ws <- as.matrix(ws)

BE4max <- BaseEditor(
  SpCas9, 
  baseEditorName = "BE4max",
  editingStrand = "original", 
  editingWeights = ws, 
  scale = TRUE
)

# 4. Define CRISPR Nickases (Cas9D10A)
Cas9D10A <- CrisprNickase(
  "Cas9D10A", 
  nickingStrand = "opposite", 
  pams = c("(3)NGG", "(3)NAG", "(3)NGA"),
  weights = c(1, 0.2593, 0.0694),
  pam_side = "3prime", 
  spacer_length = 20
)
```
*Note on inputs/outputs:* Input is nuclease specifications and weight files; output is S4 objects representing custom CRISPR nucleases, base editors, and nickases.

## When to Use
- **Nuclease Representation:** Represent CRISPR nucleases (e.g., SpCas9, SaCas9, AsCas12a) and restriction enzymes (e.g., EcoRI, HgaI) using S4 classes `CrisprNuclease` and `Nuclease`.
- **Genomic Range Extraction:** Extract genomic coordinates of PAM, protospacer, and target sequences using `getPamRanges`, `getProtospacerRanges`, and `getTargetRanges`.
- **Base Editor Modeling:** Represent base editors (e.g., BE4max) with custom editing weights using `BaseEditor`.
- **CRISPR Nickase Modeling:** Represent CRISPR nickases (e.g., Cas9D10A, Cas9H840A) that create single-strand breaks using `CrisprNickase`.
- **Sequence Extraction:** Extract protospacer and PAM sequences from target sequences using `extractProtospacerFromTarget` and `extractPamFromTarget`.

## When NOT to Use
- **Full Guide RNA Design:** For comprehensive guide RNA design, off-target search, or genomic alignment, use higher-level packages in the `crisprVerse` ecosystem (like `crisprDesign`) rather than the low-level representation classes in `crisprBase`.
- **General Genomic Arithmetic:** For general genomic arithmetic unrelated to CRISPR spacer/PAM coordinates, use standard `GenomicRanges` functions directly.

## Data Requirements
- **Target Sequences:** Character vectors of target sequences (protospacer + PAM) or genomic coordinates (chromosome, PAM site, strand).
- **Example Structure:**
  ```r
  targets <- c("AGGTGCTGATTGTAGTGCTGCGG", "AGGTGCTGATTGTAGTGCTGAGG")
  chr <- rep("chr7", 2)
  pam_site <- rep(200, 2)
  strand <- c("+", "-")
  ```

## Key Parameters
- **nucleaseName**: A string specifying the name of the nuclease.
- **targetType**: Specifies if the nuclease targets "DNA" or "RNA".
- **pams**: Character vector of PAM sequences recognized by the nuclease.
- **pam_side**: Side of the PAM sequence relative to the protospacer ("5prime" or "3prime").
- **spacer_length**: Default spacer length (e.g., 20 for SpCas9).
- **nickingStrand**: Strand cleaved by a nickase ("original" or "opposite").
- **editingStrand**: Strand where editing happens with respect to the target protospacer ("original" or "opposite").
- **scale** (TRUE): Logical indicating whether to scale editing weights between 0 and 1.

## Best Practices
- **Rebase Convention:** Use the Rebase convention to represent motif sequences (e.g., adding `^` to specify the cleavage site).
- **Expand Motifs:** Use `expand = TRUE` in `motifs()` to expand IUPAC nucleotide codes into all valid combinations of A/C/G/T.
- **Cut Site Extraction:** Use `cutSites()` to extract cut site coordinates relative to the PAM site to ensure correct genomic coordinate mapping.
- **Scale Editing Weights:** Scale custom editing weights using `scale = TRUE` in `BaseEditor` to ensure they are normalized between 0 and 1.

## Common Pitfalls
- **Confusing Spacer and Protospacer Sequences:** Remember that for RNA-targeting nucleases (like Cas13d), the spacer sequence is the reverse complement of the protospacer sequence, whereas for DNA-targeting nucleases they are identical.
- **Incorrect Row Names in Base Editor Weight Matrices:** Ensure row names correspond exactly to nucleotide substitutions (e.g., "C2T", "G2A") and column names correspond to relative positions with respect to the PAM site.

## Alternatives
- **crisprDesign**: For comprehensive gRNA design, annotation, and off-target analysis.
- **Biostrings**: For general biological sequence manipulation and motif matching without CRISPR-specific S4 classes.

## Citations
- Arbab et al. 2020, Cell (Base editing outcomes and weights)
- Komor et al. 2016, Nature (Cytosine base editors)
- Roberts et al. 2010, Nucleic Acids Research (REBASE database)

## References
- Homepage: https://bioconductor.org/packages/crisprBase
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/crisprBase/inst/doc/crisprBase.html
