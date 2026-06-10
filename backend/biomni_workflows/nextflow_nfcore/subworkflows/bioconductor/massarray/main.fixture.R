# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("MassArray")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(MassArray)

sequence <- "CCAGGTCCAAAGGTTCAGACCAGTCTGAA>CCTGTCCAGGGGCACTCCATATTTTCC"
sequence <- paste(sequence, "TACCTGTCCCTCTTTGCTTGTAAAAACAAATTAAACAGGGA", sep="")
sequence <- paste(sequence, "TCCCAGCAACTTCGGGGCATGTGTGTAACTGTGCAAGGAGC", sep="")
sequence <- paste(sequence, "GCGAAGCCCAGAGCATCGCCCTAGAGTTCGGGCCGCAGCTG", sep="")
sequence <- paste(sequence, "CAGAGGCACATCTGGAAAAGGGGGAGGGGTCGAAGCGGAGG", sep="")
sequence <- paste(sequence, "GGACAAGAAGCCCCCAAACGACTAGCTTCTGGGTGCAGAGT", sep="")
sequence <- paste(sequence, "CTGTGTCAC(CG)GGGGTTAGTTACCTGTCCTACGTTGATG", sep="")
sequence <- paste(sequence, "AATCCGTACTTGCTGGCTATGCGGTCTGCCTCCGCGAATCC", sep="")
sequence <- paste(sequence, "GC(CG)GC<GATCTTCACTGCCCAGTGGTTGGTGTA", sep="")

writeLines(sequence, "sequence")