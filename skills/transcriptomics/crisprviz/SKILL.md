---
name: bioconductor-crisprviz
description: Provides functionalities to visualize and contextualize CRISPR guide RNAs (gRNAs) on genomic tracks across nucleases and applications. Works in conjunction with the crisprBase and crisprDesign Bioconductor packages. Plots are produced using the Gviz framework.
when_to_use: Use when: Provides functionalities to visualize and contextualize CRISPR guide RNAs (gRNAs) on genomic tracks across nucleases and; Introduction to crisprViz. Not for: Requires R ≥ 4.2.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# crisprViz

## Workflows

### Standard Workflow

```r
library(crisprViz)
library(BSgenome.Hsapiens.UCSC.hg38)
data("krasGuideSet", package="crisprViz")
data("krasGeneModel", package="crisprViz")

plotGuideSet(krasGuideSet[1:4], geneModel=krasGeneModel, targetGene="KRAS")
```
*Inputs: A `GuideSet` object (`krasGuideSet`) and a gene model `GRangesList` (`krasGeneModel`). Outputs: A genomic track plot visualizing the gRNAs against the gene model.*

### Compare Multiple Guidesets

```r
library(crisprViz)
library(BSgenome.Hsapiens.UCSC.hg38)
data("cas9GuideSet", package="crisprViz")
data("cas12aGuideSet", package="crisprViz")
data("ltn1GeneModel", package="crisprViz")

plotMultipleGuideSets(list(SpCas9=cas9GuideSet, AsCas12a=cas12aGuideSet),
                      geneModel=ltn1GeneModel,
                      targetGene="LTN1",
                      bsgenome=BSgenome.Hsapiens.UCSC.hg38,
                      margin=0.2,
                      gcWindow=10)
```
*Inputs: A list of `GuideSet` objects for different nucleases, a gene model, and a reference `BSgenome` object. Outputs: A multi-track genomic plot comparing target distributions and GC content.*

## When to Use
- **gRNA Track Visualization**: Visualizing gRNA cutting locations against target genes or genomic regions using `plotGuideSet`.
- **Nuclease Comparison**: Comparing multiple `GuideSet` objects targeting the same region side-by-side using `plotMultipleGuideSets`.
- **Genomic Annotations**: Adding genomic annotations (e.g., repeat elements, CAGE peaks, DNase I hypersensitivity sites) to gRNA plots using the `annotations` argument.
- **Score-Based Color Coding**: Coloring gRNAs based on on-target efficiency scores (e.g., DeepHF) using the `onTargetScore` argument.

## When NOT to Use
- **Unsupported R/Bioconductor Versions**: Do not use if R version is less than 4.2.0 or Bioconductor version is less than 3.16.
- **gRNA Design or Scoring**: Do not use for designing gRNAs or calculating scores directly (use `crisprDesign` and `crisprScore` instead).

## Data Requirements
- **GuideSet**: A `GuideSet` object containing candidate gRNAs (e.g., `krasGuideSet`).
- **Gene Model**: A gene model represented as a `GRangesList` object (e.g., `krasGeneModel`).
- **Reference Genome**: A `BSgenome` object for genomic sequence visualization (e.g., `BSgenome.Hsapiens.UCSC.hg38`).

## Key Parameters
- **geneModel** (no default): A `GRangesList` object describing the gene structure.
- **targetGene** (no default): Character string specifying the name of the target gene.
- **from** (NULL): Numeric coordinate specifying the start of the plot window.
- **to** (NULL): Numeric coordinate specifying the end of the plot window.
- **extend.left** (0): Numeric value to extend the plot window to the left.
- **extend.right** (0): Numeric value to extend the plot window to the right.
- **showGuideLabels** (TRUE): Logical indicating whether to display gRNA labels.
- **pamSiteOnly** (FALSE): Logical indicating whether to plot only the PAM site instead of the full protospacer.
- **onTargetScore** (NULL): Character string specifying the metadata column name containing on-target scores.
- **annotations** (NULL): Named list of `GRanges` objects representing genomic annotations.
- **gcWindow** (NULL): Integer specifying the window size for calculating percent GC content.

## Best Practices
- **Window Adjustment**: Adjust the plot window manually using `from`, `to`, `extend.left`, and `extend.right` to show the entire gene or focus on a specific exon.
- **Crowding Prevention**: Set `showGuideLabels = FALSE` when plotting a large number of candidate gRNAs to avoid crowding the plot space.
- **PAM Site Only**: Set `pamSiteOnly = TRUE` when visualizing many overlapping gRNAs in a small window to simplify the plot.
- **Pre-filtering**: Filter out gRNAs overlapping repeat elements or SNPs using `crisprDesign::removeRepeats` before plotting to ensure high-quality selections.

## Common Pitfalls
- **Rendering Errors**: Plotting too many gene isoforms or gRNAs in a small graphical device, resulting in rendering errors. Fix: Increase the height/width of the plot space using `grDevices::quartz` or similar device settings.

## Alternatives
- **Gviz**: For general genomic track visualization (which `crisprViz` is built upon).
- **biovizBase**: For nucleotide color schemes and basic genomic plotting utilities.

## Citations
- No specific primary publication is cited in the vignette text, but the package is part of the `crisprVerse` ecosystem.

## References
- Homepage: bioconductor.org/packages/crisprViz
- Vignette: bioconductor.org/packages/release/bioc/vignettes/crisprViz/inst/doc/introduction.html
