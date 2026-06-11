# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("diffuStats")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(diffuStats)

# 1. Reproduce the vignette's data-preparation code
# The vignette loads 'graph_toy' directly from the package data.
data("graph_toy")

# The workflow reads 'node_scores.csv' as a data frame with row names.
# The vignette uses 'input_mat' from 'graph_toy' as an example of multiple scores.
# This fits the structure of a CSV with row names and multiple columns.
scores_df_to_write <- graph_toy$input_mat

# 2. Serialize the objects to the declared input files

# Save the graph object as 'network.graph' using saveRDS
saveRDS(graph_toy, "network.graph")

# Save the scores matrix as 'node_scores.csv'.
# Convert to data.frame to ensure write.csv handles it correctly,
# and include row names as the first column, matching the read.csv(..., row.names = 1) call.
write.csv(as.data.frame(scores_df_to_write), "node_scores.csv", row.names = TRUE)