# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("rtracklayer", "GenomicRanges", "humanStemCell")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(rtracklayer)
library(GenomicRanges)
library(humanStemCell)

# Generate regions.bed using the vignette's targetTrack
data(targets, package="rtracklayer")
targetRanges <- IRanges(targets$start, targets$end)
targetTrack <- with(targets, 
                    GRangesForUCSCGenome("hg18", chrom, targetRanges, strand, 
                                         name, target))
export(targetTrack, "regions.bed")

# Generate coldata.csv using the vignette's fhesc ExpressionSet
data(fhesc, package="humanStemCell")
write.csv(pData(fhesc), "coldata.csv", row.names=TRUE)