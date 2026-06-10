# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("GenomicRanges")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(GenomicRanges)

promoters.gr <- GRanges(
    seqnames = "chr1",
    ranges = IRanges(start = c(1000, 2000, 3000, 4000, 5000), width = 100),
    name = c("promoter_A", "promoter_B", "promoter_C", "promoter_D", "promoter_E")
)

tfbs.gr <- GRanges(
    seqnames = "chr1",
    ranges = IRanges(start = c(1050, 2050, 3050, 4050, 5050), width = 20),
    name = c("TF_1", "TF_2", "TF_1", "TF_3", "TF_2")
)

saveRDS(promoters.gr, "promoters.gr")
saveRDS(tfbs.gr, "tfbs.gr")