# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("crisprScore")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(crisprScore)

# Data preparation for getCRISPRaterScores
spacer_crisprater <- "ATCGATGCTGATGCTAGATA"

# Data preparation for getRuleSet1Scores
flank5_ruleset1 <- "ACCT"
spacer_ruleset1 <- "ATCGATGCTGATGCTAGATA"
pam_ruleset1 <- "AGG"
flank3_ruleset1 <- "TTG"
input_ruleset1 <- paste0(flank5_ruleset1, spacer_ruleset1, pam_ruleset1, flank3_ruleset1)

# Combine sequences into a character vector for the input file
user_sequences <- c(
    spacer_crisprater,
    input_ruleset1
)

# Serialize the object to user_sequences.txt
writeLines(user_sequences, "user_sequences.txt")