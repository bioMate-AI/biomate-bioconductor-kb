# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("crisprScore")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(crisprScore)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# The workflow reads the 'spacer' sequences from user_sequences.txt.
# The vignette provides an example 'spacer' for getCRISPRscanScores.
spacer_vignette <- "ATCGATGCTGATGCTAGATA" #20bp

# 2. Serialize that object to EACH declared input file
# The workflow reads user_sequences.txt using readLines, expecting one spacer per line.
writeLines(spacer_vignette, "user_sequences.txt")