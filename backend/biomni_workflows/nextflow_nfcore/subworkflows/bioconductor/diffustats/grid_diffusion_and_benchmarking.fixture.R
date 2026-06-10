# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("igraph", "diffuStats", "igraphdata")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(igraph)
library(diffuStats)
library(igraphdata)

set.seed(1)

data(yeast)

yeast <- diffuStats::largest_cc(yeast)

perc <- .5

nodes_A <- V(yeast)[Class %in% "A"]$name
nodes_unlabelled <- V(yeast)[Class %in% c(NA, "U")]$name
nodes_notA <- setdiff(V(yeast)$name, c(nodes_A, nodes_unlabelled))

known_A <- sample(nodes_A, perc*length(nodes_A))
known_notA <- sample(nodes_notA, perc*length(nodes_notA))
known