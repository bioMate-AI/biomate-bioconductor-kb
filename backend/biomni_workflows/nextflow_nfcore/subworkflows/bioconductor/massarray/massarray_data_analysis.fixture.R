# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("MassArray")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(MassArray)

# 1. Copy Example.txt from the package's extdata directory
data.path <- system.file("extdata", package="MassArray")
example_src <- list.files(data.path, pattern="Example.txt", full.names=TRUE, recursive=TRUE)

if (length(example_src) > 0 && file.exists(example_src[1])) {
    file.copy(example_src[1], "Example.txt", overwrite=TRUE)
} else {
    # Fallback: create a dummy Example.txt if not found
    dummy_data <- data.frame(
        Well = c("A01", "A02"),
        Sample = c("Sample1", "Sample2"),
        Mass = c(3000, 3100),
        Area = c(100, 150),
        SNR = c(10, 12)
    )
    write.table(dummy_data, "Example.txt", sep="\t", row.names=FALSE, quote=FALSE)
}

# 2. Create the sequence string as defined in the vignette
sequence <- "CCAGGTCCAAAGGTTCAGACCAGTCTGAA>CCTGTCCAGGGGCACTCCATATTTTCC"
sequence <- paste(sequence, "TACCTGTCCCTCTTTGCTTGTAAAAACAAATTAAACAGGGA", sep="")
sequence <- paste(sequence, "TCCCAGCAACTTCGGGGCATGTGTGTAACTGTGCAAGGAGC", sep="")
sequence <- paste(sequence, "GCGAAGCCCAGAGCATCGCCCTAGAGTTCGGGCCGCAGCTG", sep="")
sequence <- paste(sequence, "CAGAGGCACATCTGGAAAAGGGGGAGGGGTCGAAGCGGAGG", sep="")
sequence <- paste(sequence, "GGACAAGAAGCCCCCAAACGACTAGCTTCTGGGTGCAGAGT", sep="")
sequence <- paste(sequence, "CTGTGTCAC(CG)GGGGTTAGTTACCTGTCCTACGTTGATG", sep="")
sequence <- paste(sequence, "AATCCGTACTTGCTGGCTATGCGGTCTGCCTCCGCGAATCC", sep="")
sequence <- paste(sequence, "GC(CG)GC<GATCTTCACTGCCCAGTGGTTGGTGTA", sep="")

# Write the sequence to a file named "sequence"
writeLines(sequence, "sequence")