# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("dce", "igraph")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(dce)
library(igraph)

# Create a simple directed acyclic graph (DAG) representing pathway topology
g <- make_graph(
  edges = c("GeneA", "GeneB", 
            "GeneA", "GeneC", 
            "GeneB", "GeneD", 
            "GeneC", "GeneD"), 
  directed = TRUE
)

# Write the network to GML format
write_graph(g, "network.gml", format = "gml")

# Create synthetic gene expression data for control samples (samples x genes)
expr_control <- data.frame(
  GeneA = c(2.1, 2.5, 2.3, 2.8, 2.2),
  GeneB = c(4.1, 4.5, 4.3, 4.8, 4.2),
  GeneC = c(1.1, 1.5, 1.3, 1.8, 1.2),
  GeneD = c(3.1, 3.5, 3.3, 3.8, 3.2),
  row.names = paste0("Ctrl_", 1:5)
)
write.csv(expr_control, "expression_control.csv", row.names = TRUE)

# Create synthetic gene expression data for treatment samples (samples x genes)
expr_treatment <- data.frame(
  GeneA = c(5.1, 5.5, 5.3, 5.8, 5.2),
  GeneB = c(2.1, 2.5, 2.3, 2.8, 2.2),
  GeneC = c(6.1, 6.5, 6.3, 6.8, 6.2),
  GeneD = c(1.1, 1.5, 1.3, 1.8, 1.2),
  row.names = paste0("Treat_", 1:5)
)
write.csv(expr_treatment, "expression_treatment.csv", row.names = TRUE)