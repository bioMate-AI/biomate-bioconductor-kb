# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("easylift", "rtracklayer")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("easylift")
library("rtracklayer")

gr <- GRanges(
  seqnames = Rle(
    c("chr1", "chr2"), 
    c(100000, 100000)
  ),
  ranges = IRanges(
    start = 1, end = 200000
  )
)
genome(gr) <- "hg19"

export(gr, "regions.bed", format = "bed")

coldata <- data.frame(
  sample = c("sample1", "sample2"),
  condition = c("control", "treatment")
)
write.csv(coldata, "coldata.csv", row.names = FALSE)