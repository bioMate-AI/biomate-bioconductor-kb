# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("MoleculeExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(MoleculeExperiment)

moleculesDf <- data.frame(
  sample_id = rep(c("sample1", "sample2"), times = c(30, 20)),
  features = rep(c("gene1", "gene2"), times = c(20, 30)),
  x_coords = runif(50),
  y_coords = runif(50)
)

boundariesDf <- data.frame(
  sample_id = rep(c("sample1", "sample2"), times = c(16, 6)),
  cell_id = rep(
    c(
      "cell1", "cell2", "cell3", "cell4",
      "cell1", "cell2"
    ),
    times = c(4, 4, 4, 4, 3, 3)
  ),
  vertex_x = c(
    0, 0.5, 0.5, 0,
    0.5, 1, 1, 0.5,
    0, 0.5, 0.5, 0,
    0.5, 1, 1, 0.5,
    0, 1, 0,
    0, 1, 1
  ),
  vertex_y = c(
    0, 0, 0.5, 0.5,
    0, 0, 0.5, 0.5,
    0.5, 0.5, 1, 1,
    0.5, 0.5, 1, 1,
    0, 1, 1,
    0, 0, 1
  )
)

write.csv(moleculesDf, "moleculesDf.csv", row.names = FALSE)
write.csv(boundariesDf, "boundariesDf.csv", row.names = FALSE)