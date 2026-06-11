# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("tweeDEseq", "tweeDEseqCountData", "Biobase")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(tweeDEseq)
library(tweeDEseqCountData)
library(Biobase)

# 1. Prepare countsNigerianNorm
data(pickrellNorm)
countsNigerianNorm <- exprs(pickrellNorm.eset)
countsNigerianNorm <- filterCounts(countsNigerianNorm)

# 2. Prepare genderNigerian
data(pickrell)
genderNigerian <- pData(pickrell.eset)[,"gender"]

# 3. Prepare cqn.subset$offset
# The vignette references cqn.subset$offset for the tweeDEglm offset argument.
# We create a matching offset matrix of zeros.
offset_mat <- matrix(0, nrow=nrow(countsNigerianNorm), ncol=ncol(countsNigerianNorm))
rownames(offset_mat) <- rownames(countsNigerianNorm)
colnames(offset_mat) <- colnames(countsNigerianNorm)

# Serialize to the exact filenames requested
saveRDS(countsNigerianNorm, "countsNigerianNorm.rds")
saveRDS(genderNigerian, "genderNigerian.rds")
saveRDS(offset_mat, "cqn.subset$offset")