# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("diggit", "diggitdata")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(diggit)
library(diggitdata)

# Load data as per vignette chunk 4
data(gbm.expression, package="diggitdata")
data(gbm.cnv, package="diggitdata")
data(gbm.aracne, package="diggitdata")
data(gbm.mindy, package="diggitdata")

# Modify gbmCNV as per vignette chunk 5
genes <- intersect(rownames(gbmExprs), rownames(gbmCNV))[1:1000]
gbmCNV <- gbmCNV[match(genes, rownames(gbmCNV)), ]

# Load gbmCNVnormal as per vignette chunk 12
data(gbm.cnv.normal, package="diggitdata")

# Save the prepared objects to .rds files
saveRDS(gbmExprs, "gbmExprs.rds")
saveRDS(gbmCNV, "gbmCNV.rds")
saveRDS(gbmTFregulon, "gbmTFregulon.rds")
saveRDS(gbmMindy, "gbmMindy.rds")
saveRDS(gbmCNVnormal, "gbmCNVnormal.rds")