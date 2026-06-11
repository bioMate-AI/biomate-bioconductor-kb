# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("EBSeq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(EBSeq)

# Reproduce the vignette's data preparation for MultiGeneMat
# This object will be serialized to "multi_condition_gene_counts.csv"
data(MultiGeneMat)

# Reproduce the vignette's definition of Conditions
# This vector will be used to create "multi_conditions.csv"
Conditions <- c("C1","C1","C2","C2","C3","C3")

# Serialize MultiGeneMat to "multi_condition_gene_counts.csv"
# The workflow reads this with `row.names = 1`, so we must include row names in the output.
# `write.csv` by default includes row names as the first column.
write.csv(MultiGeneMat, "multi_condition_gene_counts.csv", row.names = TRUE)

# Create a data frame for the conditions, matching the expected format for "multi_conditions.csv"
# The workflow reads this with `header = TRUE` and `stringsAsFactors = FALSE`.
# We create a data frame with a single column named "Condition".
cond_data_df <- data.frame(Condition = Conditions, stringsAsFactors = FALSE)

# Serialize the conditions data frame to "multi_conditions.csv"
# `write.csv` by default writes a header. We explicitly set `row.names = FALSE`
# as the workflow does not expect row names for this file.
write.csv(cond_data_df, "multi_conditions.csv", row.names = FALSE)