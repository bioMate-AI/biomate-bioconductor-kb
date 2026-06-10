# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("heatmaps", "rtracklayer", "GenomicRanges", "BSgenome.Drerio.UCSC.danRer7")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(heatmaps)
library(rtracklayer)
library(GenomicRanges)
library(BSgenome.Drerio.UCSC.danRer7)

heatmaps_file <- function(fn) system.file("extdata", fn, package="heatmaps")

# Load the example data from the heatmaps package
zf_30p_promoters <- import(heatmaps_file("30pEpi_proms.bed"), genome=seqinfo(Drerio))
h3k4me3_30p_pos <- readRDS(heatmaps_file("H3K4me3_30p_pos.rds"))
h3k4me3_30p_neg <- readRDS(heatmaps_file("H3K4me3_30p_neg.rds"))

# Combine positive and negative strand coverage
h3k4me3_30p <- h3k4me3_30p_pos + h3k4me3_30p_neg

# Write the required input files
export(zf_30p_promoters, "genomic_intervals.bed", format="BED")
saveRDS(h3k4me3_30p, "coverage_data.rds")