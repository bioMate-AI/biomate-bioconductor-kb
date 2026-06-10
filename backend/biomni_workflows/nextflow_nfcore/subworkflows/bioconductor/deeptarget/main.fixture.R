# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DeepTarget")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DeepTarget)

# Reproduce the vignette's data-preparation code
data("OntargetM")

# Extract and serialize the components to the specified CSV files
# For secondary_prism.csv, avana_CRISPR.csv, mutations_mat.csv, expression_20Q4.csv:
# The workflow reads them as matrices with row names from the first column.
# Therefore, write.csv should include row names.
write.csv(OntargetM$secondary_prism, "secondary_prism.csv", row.names = TRUE)
write.csv(OntargetM$avana_CRISPR, "avana_CRISPR.csv", row.names = TRUE)
write.csv(OntargetM$mutations_mat, "mutations_mat.csv", row.names = TRUE)
write.csv(OntargetM$expression_20Q4, "expression_20Q4.csv", row.names = TRUE)

# For DrugMetadata.csv:
# The workflow reads it as a data frame without specifying row names.
# Therefore, write.csv should not include row names.
write.csv(OntargetM$DrugMetadata, "DrugMetadata.csv", row.names = FALSE)