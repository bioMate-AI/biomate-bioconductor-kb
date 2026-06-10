# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("crisprScore")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(crisprScore)

input_file_name <- "user_sequences.txt"

flank5_1 <- "ACCT"
spacer_1 <- "ATCGATGCTGATGCTAGATA"
pam_1 <- "AGG"
flank3_1 <- "TTG"
sequence_1 <- paste0(flank5_1, spacer_1, pam_1, flank3_1)

flank5_2 <- "GGTA"
spacer_2 <- "GCTAGCTAGCTAGCTAGCTA"
pam_2 <- "TGG"
flank3_2 <- "CAA"
sequence_2 <- paste0(flank5_2, spacer_2, pam_2, flank3_2)

flank5_3 <- "CCTA"
spacer_3 <- "TAGCTAGCTAGCTAGCTAGC"
pam_3 <- "CGG"
flank3_3 <- "GTT"
sequence_3 <- paste0(flank5_3, spacer_3, pam_3, flank3_3)

user_sequences <- c(sequence_1, sequence_2, sequence_3)

writeLines(user_sequences, con = input_file_name)