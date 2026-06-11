# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("PPInfer", "igraph")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(PPInfer)
library(igraph)

data(litG)
if (exists("igraph.from.graphNEL")) {
    litG_igraph <- igraph.from.graphNEL(litG)
} else {
    litG_igraph <- graph_from_graphnel(litG)
}

sg <- decompose(litG_igraph, min.vertices = 50)
sg <- sg[[1]]

K <- net.kernel(sg)

data(exampleRanks)
geneNames <- names(exampleRanks)

set.seed(1)
gene.names <- sample(geneNames, length(V(sg)))
rownames(K) <- paste0("9606.", gene.names)
colnames(K) <- paste0("9606.", gene.names)

saveRDS(K, "K9606.rds")

myInterestingGenes <- sample(gene.names, 10)
writeLines(myInterestingGenes, "target_proteins.txt")