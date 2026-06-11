# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("cfTools", "utils")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(cfTools)
library(utils) # For system.file

# Get the path to the demo data directory within the package
demo.dir <- system.file("data", package="cfTools")

# 3.1 Merge paired-end sequencing reads to fragment-level
PEReads <- file.path(demo.dir, "demo.sorted.bed.txt.gz")
fragInfo <- MergePEReads(PEReads)

# 3.2 Merge methylation states of CpGs on two strands to fragment-level
CpG_OT <- file.path(demo.dir, "CpG_OT_demo.txt.gz")
CpG_OB <- file.path(demo.dir, "CpG_OB_demo.txt.gz")
methInfo <- MergeCpGs(CpG_OT, CpG_OB)

# 3.3 Generate fragment-level information about methylation states
fragMeth <- GenerateFragMeth(fragInfo, methInfo)

# Serialize the object to the declared input file "cfsort_reads.txt.gz"
# The workflow reads this file as a tab-separated file with a header.
output_file <- "cfsort_reads.txt.gz"
write.table(fragMeth, file = output_file, sep = "\t", row.names = FALSE, col.names = TRUE, quote = FALSE)