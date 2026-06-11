# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("SimFFPE", "Biostrings")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(SimFFPE)
library(Biostrings)

# 1. example.fasta
fasta_src <- system.file("extdata", "example.fasta", package = "SimFFPE")
if (file.exists(fasta_src)) {
    file.copy(fasta_src, "example.fasta", overwrite = TRUE)
} else {
    seqs <- DNAStringSet(c("1" = "AGACTAACATGGATCCTTTCTTTCC", "2" = "ACATTTCCATTTGGTAGGCGGGGCA"))
    writeXStringSet(seqs, "example.fasta")
}

# 2. regionsSim.txt
regions_src <- system.file("extdata", "regionsSim.txt", package = "SimFFPE")
if (file.exists(regions_src)) {
    file.copy(regions_src, "regionsSim.txt", overwrite = TRUE)
} else {
    regions <- data.frame(V1 = c("1", "2"), V2 = c(20000001, 20000001), V3 = c(20000100, 20000100))
    write.table(regions, "regionsSim.txt", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
}

# 3. PhredScoreProfile1.txt
phred_src <- system.file("extdata", "PhredScoreProfile1.txt", package = "SimFFPE")
if (file.exists(phred_src)) {
    file.copy(phred_src, "PhredScoreProfile1.txt", overwrite = TRUE)
} else {
    header <- paste(1:100, collapse="\t")
    mat <- matrix(40, nrow=4, ncol=100)
    rownames(mat) <- c("A", "C", "G", "T")
    
    writeLines(header, "PhredScoreProfile1.txt")
    write.table(mat, "PhredScoreProfile1.txt", sep="\t", quote=FALSE, col.names=FALSE, append=TRUE)
}