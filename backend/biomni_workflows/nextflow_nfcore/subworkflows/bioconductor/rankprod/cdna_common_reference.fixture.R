# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("RankProd")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(RankProd)

# Reproduce the vignette's data-preparation code for cDNA array data
# This corresponds to "Identification of differentially expressed genes – cDNA array" section 4.1
# in the RankProd vignette.
data(lymphoma)

# Recreate the 'M' matrix as shown in chunk 17 of the vignette
refrs <- (1:8)*2-1
samps <- (1:8)*2
M <- lym.exp[,samps]-lym.exp[,refrs]

# Serialize the 'M' matrix to the specified input file 'cdna_intensities.tsv'
# The workflow reads this file using:
# as.matrix(read.delim(input_file, row.names = 1, header = TRUE, check.names = FALSE))
# So, we need to write a tab-separated file with row names as the first column
# and column names as the header.
write.table(M, file = "cdna_intensities.tsv", sep = "\t", quote = FALSE, row.names = TRUE, col.names = TRUE)