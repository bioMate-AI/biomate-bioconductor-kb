# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("singscore", "GSEABase")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(singscore)
library(GSEABase)

# Load the datasets provided by the singscore package
data("tgfb_expr_10_se", package = "singscore")
data("tgfb_gs_up", package = "singscore")
data("tgfb_gs_dn", package = "singscore")

# Serialize the S4 objects to the working directory as expected by the workflow
saveRDS(tgfb_expr_10_se, "tgfb_expr_10_se.rds")
saveRDS(tgfb_gs_up, "tgfb_gs_up.rds")
saveRDS(tgfb_gs_dn, "tgfb_gs_dn.rds")