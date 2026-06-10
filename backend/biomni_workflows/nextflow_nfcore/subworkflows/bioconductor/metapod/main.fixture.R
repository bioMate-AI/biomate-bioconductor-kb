# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("metapod")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(metapod)

set.seed(42)

# Reproduce the vignette's data generation
p1 <- rbeta(10000, 0.5, 1)
p2 <- rbeta(10000, 0.5, 1)
p <- rbeta(10000, 0.5, 1)
g <- sample(100, length(p), replace=TRUE)
logfc1 <- rnorm(10000)
logfc2 <- rnorm(10000)

# Serialize to the requested input files
counts <- data.frame(
    p1 = p1,
    p2 = p2,
    p = p,
    g = g,
    logfc1 = logfc1,
    logfc2 = logfc2
)
write.csv(counts, "counts.csv", row.names = FALSE)

coldata <- data.frame(
    variable = colnames(counts),
    type = c("pvalue", "pvalue", "pvalue", "group", "logfc", "logfc")
)
write.csv(coldata, "coldata.csv", row.names = FALSE)