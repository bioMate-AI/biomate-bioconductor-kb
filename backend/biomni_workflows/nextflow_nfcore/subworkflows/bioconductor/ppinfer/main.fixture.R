# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("PPInfer", "igraph", "graph")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(PPInfer)
library(igraph)
library(graph)

# 1. Prepare network.gml
data(litG)
litG_igraph <- igraph.from.graphNEL(litG)
sg <- decompose(litG_igraph, min.vertices = 50)
sg <- sg[[1]]           # largest subgraph
write_graph(sg, "network.gml", format = "gml")

# 2. Prepare target_proteins.txt
data(exampleRanks)
geneNames <- names(exampleRanks)
set.seed(1)
gene.names <- sample(geneNames, length(V(sg)))
myInterestingGenes <- sample(gene.names, 10)
writeLines(as.character(myInterestingGenes), "target_proteins.txt")

# 3. Prepare pathways.gmt
data(examplePathways)
gmt_lines <- unname(mapply(function(name, genes) {
    paste(c(name, name, genes), collapse = "\t")
}, names(examplePathways), examplePathways))
writeLines(gmt_lines, "pathways.gmt")