# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("RCyjs", "graph")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(RCyjs)
library(graph)

nodes <- c("A", "T")
g <- graphNEL(nodes, edgemode="directed")
g <- graph::addEdge("A", "T", g)

nodeDataDefaults(g, attr="label") <- "undefined"
nodeDataDefaults(g, attr="type") <- "undefined"
nodeDataDefaults(g, attr="flux") <- 0
edgeDataDefaults(g, attr="edgeType") <- "undefined"

nodeData(g, nodes, attr="label") <- c("Activator", "Target")
nodeData(g, nodes, attr="type") <- c("ligand", "receptor")
edgeData(g, "A", "T", attr="edgeType") <- "binds"

# Write the required input.csv file
write.csv(data.frame(
  node = nodes,
  label = c("Activator", "Target"),
  type = c("ligand", "receptor")
), "input.csv", row.names = FALSE)