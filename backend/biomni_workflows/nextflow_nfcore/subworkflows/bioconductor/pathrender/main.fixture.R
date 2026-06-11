# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("pathRender", "graph", "Rgraphviz", "ALL", "hgu95av2.db")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(pathRender)
library(graph)
library(Rgraphviz)
library(ALL)
library(hgu95av2.db)

# Load the pathway graph
data(pancrCaIni)

# Load the ALL dataset
data(ALL)

# Reduce the ExpressionSet to the nodes of the pathway graph
collap1 <- reduceES(ALL, nodes(pancrCaIni), revmap(hgu95av2SYMBOL), "symbol", mean)

# Serialize the reduced expression matrix to the required input file
write.csv(exprs(collap1), file = "input.csv", row.names = TRUE)