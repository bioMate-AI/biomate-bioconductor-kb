# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("TOAST", "EpiDISH")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(TOAST)
library(EpiDISH)

data("RA_100samples")

Y_raw <- RA_100samples$Y_raw

design <- RA_100samples$Pheno

Blood_ref <- RA_100samples$Blood_ref

refinx <- findRefinx(Y_raw, nmarker = 1000)

Y_subset <- Y_raw[refinx,]
Ref_subset <- as.matrix(Blood_ref[refinx,])

outT <- epidish(beta.m = Y_subset, ref.m = Ref_subset, method = "RPC")
Prop <- outT$estF

saveRDS(Y_raw, "Y_raw.rds")
saveRDS(Prop, "Prop.rds")
saveRDS(design, "design.rds")