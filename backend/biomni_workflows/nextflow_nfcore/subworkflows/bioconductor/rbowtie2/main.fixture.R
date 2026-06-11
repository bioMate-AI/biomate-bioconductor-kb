# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Rbowtie2")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(Rbowtie2)

# Locate and copy reads_1.fq
reads_1_src <- system.file(package="Rbowtie2", "extdata", "adrm", "reads_1.fq")
if (file.exists(reads_1_src)) {
    file.copy(reads_1_src, "reads_1.fq", overwrite = TRUE)
} else {
    # Fallback synthetic FASTQ if not found
    writeLines(c(
        "@read1",
        "AGATCGGAAGAGCACACGTCTGAACTCCAGTCACCACCTAATCTCGTATGCCGTCTTCTGCTTG",
        "+",
        "IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII"
    ), "reads_1.fq")
}

# Locate and copy reads_2.fq
reads_2_src <- system.file(package="Rbowtie2", "extdata", "adrm", "reads_2.fq")
if (file.exists(reads_2_src)) {
    file.copy(reads_2_src, "reads_2.fq", overwrite = TRUE)
} else {
    # Fallback synthetic FASTQ if not found
    writeLines(c(
        "@read1",
        "AGATCGGAAGAGCGTCGTGTAGGGAAAGAGTGTAGATCTCGGTGGTCGCCGTATCATT",
        "+",
        "IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII"
    ), "reads_2.fq")
}

# Locate and copy a reference FASTA file, or create a synthetic one
refs_src <- list.files(system.file("extdata", package="Rbowtie2"), pattern="\\.fa$|\\.fasta$", recursive=TRUE, full.names=TRUE)
if (length(refs_src) > 0 && file.exists(refs_src[1])) {
    file.copy(refs_src[1], "refs", overwrite = TRUE)
} else {
    # Fallback synthetic FASTA if not found
    writeLines(c(
        ">chr1",
        "AGATCGGAAGAGCACACGTCTGAACTCCAGTCACCACCTAATCTCGTATGCCGTCTTCTGCTTG",
        ">chr2",
        "AGATCGGAAGAGCGTCGTGTAGGGAAAGAGTGTAGATCTCGGTGGTCGCCGTATCATT"
    ), "refs")
}