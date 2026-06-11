# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("crisprBwa")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(crisprBwa)

# 1. genome_fasta.fa
fasta_file <- system.file("example", "chr12.fa", package="crisprBwa")
if (file.exists(fasta_file)) {
    file.copy(fasta_file, "genome_fasta.fa", overwrite = TRUE)
} else {
    # Fallback synthetic FASTA if the package file is missing
    writeLines(c(">chr12", "AACGGGGAGATTGGTAAGCGGAGTGT"), "genome_fasta.fa")
}

# 2. seeds_vector
seeds <- c("GTAAGCGGAGTGT", "AACGGGGAGATTG")
saveRDS(seeds, "seeds_vector")