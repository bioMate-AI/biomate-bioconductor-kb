# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("kebabs", "Biostrings")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(kebabs)
library(Biostrings)

# Load the CCoil dataset used in the vignette for annotation-specific kernels
data(CCoil)

# Write the biological sequences to a FASTA file
writeXStringSet(ccseq, "sequences.fasta")

# Write the annotations (character strings of identical length to sequences) to a text file
writeLines(ccannot, "annotations.txt")

# Write the class labels to a text file
writeLines(as.character(yCC), "labels.txt")