# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("SingleMoleculeFootprinting", "GenomicRanges")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(SingleMoleculeFootprinting)
library(GenomicRanges)

# Reproduce the RegionOfInterest from the vignette
RegionOfInterest = GRanges("chr6", IRanges(88106000, 88106500))

# Write to regions.bed
regions_df <- as.data.frame(RegionOfInterest)
write.table(
  regions_df[, c("seqnames", "start", "end")], 
  file = "regions.bed", 
  sep = "\t", 
  quote = FALSE, 
  row.names = FALSE, 
  col.names = FALSE
)

# Create a coldata.csv based on the sample name seen in the vignette's output
coldata <- data.frame(
  sample = "SMF_MM_TKO_DE_",
  condition = "TKO"
)
write.csv(coldata, file = "coldata.csv", row.names = FALSE)