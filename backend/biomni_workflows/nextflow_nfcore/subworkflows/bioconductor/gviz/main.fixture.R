# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Gviz", "GenomicRanges")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(Gviz)
library(GenomicRanges)

# Load the example dataset from the vignette
data(cpgIslands)

# 1. Create twoGroups: GRanges object containing numeric metadata columns
twoGroups <- cpgIslands
mcols(twoGroups)$group1 <- runif(length(twoGroups), 1, 10)
mcols(twoGroups)$group2 <- runif(length(twoGroups), 1, 10)
saveRDS(twoGroups, "twoGroups.rds")

# 2. Create bgFile.bedGraph: bedGraph file containing genomic coordinates and a single numeric score column
# bedGraph uses 0-based start and 1-based end coordinates
bg_data <- data.frame(
  chrom = as.character(seqnames(cpgIslands)),
  chromStart = start(cpgIslands) - 1,
  chromEnd = end(cpgIslands),
  score = runif(length(cpgIslands), 1, 10)
)
write.table(bg_data, "bgFile.bedGraph", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)