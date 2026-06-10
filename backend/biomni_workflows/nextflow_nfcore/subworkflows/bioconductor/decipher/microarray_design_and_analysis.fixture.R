# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DECIPHER")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DECIPHER)

# fas: FASTA file of sequences
fas_src <- system.file("extdata", "Bacteria_175seqs.fas", package="DECIPHER")
if (file.exists(fas_src)) {
    file.copy(fas_src, "fas")
} else {
    # Fallback synthetic FASTA
    writeLines(c(">seq1", "ACGT", ">seq2", "TGCA"), "fas")
}

# b: matrix of background-subtracted probe brightnesses
# Creating a synthetic matrix of probe brightnesses
b_matrix <- matrix(runif(100, min=100, max=10000), nrow=10, ncol=10)
rownames(b_matrix) <- paste0("Probe_", 1:10)
colnames(b_matrix) <- paste0("Sample_", 1:10)
write.table(b_matrix, "b", sep="\t", quote=FALSE, col.names=NA)