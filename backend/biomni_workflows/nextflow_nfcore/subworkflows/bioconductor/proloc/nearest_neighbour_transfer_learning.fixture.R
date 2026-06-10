# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("pRoloc", "pRolocdata")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("pRoloc")
library("pRolocdata")

data("andy2011")
data("andy2011goCC")

primary_df_to_write <- as.data.frame(exprs(andy2011))
write.csv(primary_df_to_write, "primary_data.csv", row.names = TRUE)

auxiliary_df_to_write <- as.data.frame(exprs(andy2011goCC))
write.csv(auxiliary_df_to_write, "auxiliary_data.csv", row.names = TRUE)