# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("SingleMoleculeFootprinting", "GenomicRanges", "rtracklayer")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressWarnings(library(SingleMoleculeFootprinting))
suppressWarnings(library(GenomicRanges))
suppressWarnings(library(rtracklayer))

# Reproduce the vignette's RegionOfInterest
RegionOfInterest = GRanges("chr6", IRanges(88106000, 88106500))
RegionOfInterest = IRanges::resize(RegionOfInterest, 80, "center")

# Serialize to regions.bed
export(RegionOfInterest, "regions.bed", format = "BED")

# Create and serialize a dummy coldata.csv
coldata <- data.frame(
  sample = "SMF_MM_TKO_DE_",
  condition = "TKO"
)
write.csv(coldata, "coldata.csv", row.names = FALSE)