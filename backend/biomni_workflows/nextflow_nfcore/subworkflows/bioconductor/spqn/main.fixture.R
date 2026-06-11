# [biomate] structured fixture (rule: class_constructor) — deterministic, no LLM
# target class: SummarizedExperiment
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("spqn")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressMessages(library(spqn))
n_g<-200; n_s<-8; .m<-matrix(rpois(n_g*n_s,10),n_g,n_s,dimnames=list(paste0("g",1:n_g),paste0("s",1:n_s))); .cd<-S4Vectors::DataFrame(condition=factor(rep(c("A","B"),length.out=n_s)),row.names=colnames(.m)); .obj<-SummarizedExperiment::SummarizedExperiment(assays=list(counts=.m),colData=.cd)
saveRDS(.obj, "gtex.rds")
