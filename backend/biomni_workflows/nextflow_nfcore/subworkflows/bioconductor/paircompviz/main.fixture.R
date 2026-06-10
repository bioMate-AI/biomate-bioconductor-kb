# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("paircompviz", "plyr")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(paircompviz)
library(plyr)

# The vignette reads "result.csv" which is not shipped with the package.
# We construct a synthetic data frame matching the exact columns and expected values 
# inferred from the vignette's data manipulation steps.
experiment <- data.frame(
  X = 1:5,
  pkg = c("pkgA", "pkgB", "pkgC", "pkgD", "pkgE"),
  dataset = c("data1", "data2", "data3", "data4", "data5"),
  obj = c("obj1", "obj2", "obj3", "obj4", "obj5"),
  grouping = c("g1", "g2", "g3", "g4", "g5"),
  nlev = c(2, 3, 4, 5, 6),
  type = c("prop", "t pool.sd", "t !pool.sd", "tukey", "wilcox"),
  error = c("ok", "broken", "ok", "broken", "ok"),
  stringsAsFactors = FALSE
)

# Write to the requested input file as well as the vignette's original filename
write.csv(experiment, "input.csv", row.names = FALSE)
write.csv(experiment, "result.csv", row.names = FALSE)