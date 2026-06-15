---
name: bioconductor-crisprdesign
description: Provides a comprehensive suite of functions to design and annotate CRISPR guide RNA (gRNAs) sequences. This includes on- and off-target search, on-target efficiency scoring, off-target scoring, full gene and TSS contextual annotations, and SNP annotation (human only). It currently support five types of CRISPR modalities (modes of perturbations): CRISPR knockout, CRISPR activation, CRISPR inhibition, CRISPR base editing, and CRISPR knockdown. All types of CRISPR nucleases are supported, including
when_to_use: Use when: Provides a comprehensive suite of functions to design and annotate CRISPR guide RNA (gRNAs) sequences; Introduction to crisprDesign. Not for: Requires R ≥ 4.2.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# crisprDesign

## Workflows

### Standard Workflow

```r
library(crisprDesign)
library(BSgenome.Hsapiens.UCSC.hg38)
data(grListExample, package="crisprDesign")
data(BE4max, package="crisprBase")

bsgenome <- BSgenome.Hsapiens.UCSC.hg38
gr <- queryTxObject(txObject=grListExample, featureType="cds", queryColumn="gene_symbol", queryValue="IQSEC3")
gr <- gr[1]

guideSet <- findSpacers(gr, bsgenome=bsgenome, crisprNuclease=BE4max, strict_overlap=FALSE)
```
*Inputs: GRangesList gene coordinates (`grListExample`), BSgenome object (`bsgenome`), and a BaseEditor/CrisprNuclease object (`BE4max`). Output: A `GuideSet` object containing designed spacer sequences.*

## When to Use
- **CRISPR Base Editing Design**: Designing and characterizing gRNAs for base editors (e.g., cytidine base editor BE4max) using `findSpacers` and predicting edited alleles with `addEditedAlleles`.
- **Gene Feature Querying**: Querying transcript objects for specific features (e.g., coding sequences) using `queryTxObject`.
- **Transcript Annotation Retrieval**: Obtaining transcript-specific annotations for predicted allele analysis using `getTxInfoDataFrame`.

## When NOT to Use
- **Unsupported R/Bioconductor Versions**: Do not use if R version is less than 4.2.0 or Bioconductor version is less than 3.16.
- **General Sequence Alignment**: For general sequence alignment tasks where specialized aligners (like Bowtie/BWA directly) are more appropriate.

## Data Requirements
- **Gene Coordinates**: A `GRangesList` object containing gene coordinates (e.g., `grListExample`).
- **Reference Genome**: A `BSgenome` object containing reference genome sequences (e.g., `BSgenome.Hsapiens.UCSC.hg38`).
- **Nuclease/Base Editor Specification**: A `BaseEditor` or `CrisprNuclease` object (e.g., `BE4max` or `SpCas9`).

## Key Parameters
- **txObject** (no default): A `GRangesList` object containing gene model coordinates used in `queryTxObject` and `getTxInfoDataFrame`.
- **featureType** (no default): Character string specifying the gene feature to query (e.g., `"cds"`).
- **crisprNuclease** (no default): A `CrisprNuclease` or `BaseEditor` object specifying the CRISPR enzyme.
- **strict_overlap** (`TRUE`): Logical indicating whether spacer sequences must strictly overlap the target region.
- **editingWindow** (NULL): Numeric vector of length 2 specifying the window of editing relative to the PAM site.
- **minEditingWeight** (`0`): Minimum editing weight required for an allele to be predicted.
- **minMutationScore** (`0.3`): Minimum predicted probability for labeling an allele with a predicted variant.

## Best Practices
- **Feature Extraction**: Use `queryTxObject` to extract specific genomic features (like `"cds"`) before running spacer design.
- **Flexible Overlaps**: Set `strict_overlap = FALSE` in `findSpacers` for base editing design to allow the editing window to extend beyond the protospacer sequence region.
- **Window Limitation**: Limit the `editingWindow` size in `addEditedAlleles` to avoid exponential increases in computing time.

## Common Pitfalls
- **Large Editing Windows**: Providing a very large `editingWindow` to `addEditedAlleles` exponentially increases computing time. Fix: Use a narrower window like `c(-20, -8)`.
- **Strict Overlaps in Base Editing**: Using `strict_overlap = TRUE` for base editing might miss spacers whose editing window extends outside the target region. Fix: Set `strict_overlap = FALSE`.

## Alternatives
- **crisprBase**: For core CRISPR functions and S4 objects.
- **crisprBowtie**: For aligning gRNA spacers to genomes using bowtie.
- **crisprBwa**: For aligning gRNA spacers to genomes using BWA.
- **crisprScore**: For calculating on- and off-target scores.
- **crisprViz**: For visualizing gRNAs using genomic tracks.

## Citations
- Koblan, Luke W, et al. 2018. "Improving Cytidine and Adenine Base Editors by Expression Optimization and Ancestral Reconstruction." Nature Biotechnology 36 (9): 843–46.

## References
- Homepage: bioconductor.org/packages/crisprDesign
- Vignette: bioconductor.org/packages/release/bioc/vignettes/crisprDesign/inst/doc/base_editing.html
