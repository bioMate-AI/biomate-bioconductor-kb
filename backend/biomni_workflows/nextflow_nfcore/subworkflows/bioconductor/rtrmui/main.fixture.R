# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("rTRMui")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(rTRMui)

# The workflow expects an input.csv file. Since no specific structure is provided 
# in the excerpt, we create a basic synthetic dataset representing typical 
# transcription factor or gene expression data as seen in the rTRMui vignette.
dummy_data <- data.frame(
  Gene = c("Pou5f1", "Sox2", "Hdac2", "Esrrb", "Sall4", "Sox15", "Klf4", "Rad21"),
  Expression = c(10.5, 12.1, 8.4, 9.2, 11.0, 7.5, 14.2, 6.8)
)

write.csv(dummy_data, file = "input.csv", row.names = FALSE)