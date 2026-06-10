# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("biocViews")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(biocViews)

# Reproduce the vignette's data-preparation code
data(biocViewsVocab)
reposPath <- system.file("doc", package="biocViews")
reposUrl <- paste("file://", reposPath, sep="")
biocViews_obj <- getBiocSubViews(reposUrl, biocViewsVocab, topTerm="Software")

# The workflow expects regions.bed and coldata.csv.
# Since biocViews does not natively use these genomic formats, we create 
# minimal valid dummy files to satisfy the workflow's input requirements.

# Generate regions.bed
bed_data <- data.frame(
  chrom = c("chr1", "chr2"),
  chromStart = c(1000, 2000),
  chromEnd = c(1500, 2500),
  name = c("region_A", "region_B"),
  score = c(0, 0),
  strand = c("+", "-")
)
write.table(bed_data, file = "regions.bed", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)

# Generate coldata.csv
coldata <- data.frame(
  sample = c("sample1", "sample2"),
  condition = c("control", "treatment"),
  replicate = c(1, 1)
)
write.csv(coldata, file = "coldata.csv", row.names = FALSE, quote = FALSE)