# [biomate] structured fixture (rule: class_constructor) — deterministic, no LLM
# target class: ExpressionSet
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("plgem")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressMessages(library(plgem))
n_g<-200; n_s<-8; .m<-matrix(rpois(n_g*n_s,10),n_g,n_s,dimnames=list(paste0("g",1:n_g),paste0("s",1:n_s))); .cd<-S4Vectors::DataFrame(condition=factor(rep(c("A","B"),length.out=n_s)),row.names=colnames(.m)); .obj<-Biobase::ExpressionSet(assayData=.m)
saveRDS(.obj, "ExpressionSet.rds")

# [biomate-fx-dual] emit each declared input under BOTH bare-token and .rds names
# so any input-staging harness collects the real serialized object under the
# exact name the workflow reads (bare token or <token>.rds).
.bm_dual <- function(b) {
  rds <- paste0(b, '.rds')
  if (file.exists(rds) && !file.exists(b)) file.copy(rds, b, overwrite=TRUE)
  if (file.exists(b) && !file.exists(rds)) file.copy(b, rds, overwrite=TRUE)
}
.bm_dual('ExpressionSet')
