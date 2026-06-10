# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Gviz", "GenomicRanges", "Rsamtools")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(Gviz)
library(GenomicRanges)
library(Rsamtools)

# Reproduce vignette data preparation
data(cpgIslands, package = "Gviz")
chr <- as.character(unique(seqnames(cpgIslands)))
gen <- genome(cpgIslands)
atrack <- AnnotationTrack(cpgIslands, name = "CpG")

data(geneModels, package = "Gviz")
grtrack <- GeneRegionTrack(geneModels, genome = gen, chromosome = chr, name = "Gene Model")

# Generate gapped.bam as required by the workflow
# Using coordinates from the vignette (chr7, around 26700000)
sam_content <- c(
  "@HD\tVN:1.0\tSO:coordinate",
  "@SQ\tSN:chr7\tLN:100000000",
  "read1\t0\tchr7\t26700100\t255\t10M100N10M\t*\t0\t0\tACGTACGTACACGTACGTAC\tIIIIIIIIIIIIIIIIIIII",
  "read2\t16\tchr7\t26700200\t255\t20M\t*\t0\t0\tACGTACGTACACGTACGTAC\tIIIIIIIIIIIIIIIIIIII"
)

writeLines(sam_content, "gapped.sam")
asBam("gapped.sam", destination = "gapped")
unlink("gapped.sam")