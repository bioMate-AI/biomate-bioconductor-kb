# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("vsn", "limma", "Biobase")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("vsn")
library("limma")
library("Biobase")

data("lymphoma", package = "vsn")

wg <- which(lymphoma$dye == "Cy3")
wr <- which(lymphoma$dye == "Cy5")

lymRG <- new("RGList", list(
    R = exprs(lymphoma)[, wr],
    G = exprs(lymphoma)[, wg]
))

lymRGwbg <- new("RGList", list(
    R = exprs(lymphoma)[, wr],
    G = exprs(lymphoma)[, wg],
    Rb = matrix(50, nrow = nrow(lymphoma), ncol = length(wr)),
    Gb = matrix(50, nrow = nrow(lymphoma), ncol = length(wg))
))

saveRDS(lymRG, "lymRG.rds")
saveRDS(lymRGwbg, "lymRGwbg.rds")