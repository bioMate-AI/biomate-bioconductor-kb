# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("TCGAutils", "rtracklayer", "GenomicRanges")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(TCGAutils)
library(rtracklayer)
library(GenomicRanges)

# Generate regions.bed
gr <- GRanges(
    seqnames = c("chr1", "chr2", "chr3"),
    ranges = IRanges(start = c(1000, 2000, 3000), width = 500),
    name = c("regionA", "regionB", "regionC"),
    score = c(100, 200, 300)
)
export(gr, "regions.bed", format = "bed")

# Generate coldata.csv using data from the vignette
data("sampleTypes", package = "TCGAutils")
write.csv(sampleTypes, file = "coldata.csv", row.names = FALSE)