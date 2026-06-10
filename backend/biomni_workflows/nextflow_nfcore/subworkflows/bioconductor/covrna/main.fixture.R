# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("covRNA", "Biobase")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(covRNA)
library(Biobase) # For exprs, fData, pData functions

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# Load the integrated Baca dataset, which contains the ExpressionSet Baca.
data(Baca)

# 2. Serialize the object to EACH declared input file in the EXACT format the workflow reads

# Save the ExpressionSet object 'Baca' to expression_set.RData
# The workflow reads this with `load("expression_set.RData", envir = env)`
save(Baca, file = "expression_set.RData")

# Extract the expression data (L_matrix equivalent) and save to L_matrix.csv
# The workflow reads this with `read.csv("L_matrix.csv", row.names = 1, check.names = FALSE)`
# `row.names = TRUE` ensures the first column contains row names, matching `row.names = 1`
write.csv(exprs(Baca), file = "L_matrix.csv", row.names = TRUE)

# Extract the gene covariates (R_df equivalent) and save to R_df.csv
# The workflow reads this with `read.csv("R_df.csv", row.names = 1, check.names = FALSE)`
write.csv(fData(Baca), file = "R_df.csv", row.names = TRUE)

# Extract the sample covariates (Q_df equivalent) and save to Q_df.csv
# The workflow reads this with `read.csv("Q_df.csv", row.names = 1, check.names = FALSE)`
write.csv(pData(Baca), file = "Q_df.csv", row.names = TRUE)