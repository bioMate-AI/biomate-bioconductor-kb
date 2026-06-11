# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("LinTInd")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(LinTInd)

copy_uncompressed <- function(in_file, out_file) {
    if (grepl("\\.gz$", in_file)) {
        con <- gzfile(in_file, "rt")
        lines <- readLines(con)
        close(con)
        writeLines(lines, out_file)
    } else {
        file.copy(in_file, out_file, overwrite = TRUE)
    }
}

# Find and prepare reference.fasta
fa_files <- list.files(
    system.file("extdata", package = "LinTInd"), 
    pattern = "\\.fasta$|\\.fa$|\\.fasta\\.gz$|\\.fa\\.gz$", 
    full.names = TRUE, 
    recursive = TRUE
)

if (length(fa_files) > 0) {
    copy_uncompressed(fa_files[1], "reference.fasta")
} else {
    # Fallback synthetic FASTA
    fa_lines <- c(
        ">reference_sequence",
        "ATGCGTACGTTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTA"
    )
    writeLines(fa_lines, "reference.fasta")
}

# Find and prepare reads.fastq
fq_files <- list.files(
    system.file("extdata", package = "LinTInd"), 
    pattern = "\\.fastq$|\\.fq$|\\.fastq\\.gz$|\\.fq\\.gz$", 
    full.names = TRUE, 
    recursive = TRUE
)

if (length(fq_files) > 0) {
    copy_uncompressed(fq_files[1], "reads.fastq")
} else {
    # Fallback synthetic FASTQ
    fq_lines <- c(
        "@read_1",
        "ATGCGTACGTTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTA",
        "+",
        "IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII"
    )
    writeLines(fq_lines, "reads.fastq")
}