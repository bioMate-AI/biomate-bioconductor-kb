# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("RCy3", "igraph")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(RCy3)
library(igraph)

# Reproduce data preparation code from RCy3 vignette, Section 4
# "My first network" example, using data.frames
nodes <- data.frame(id=c("node 0","node 1","node 2","node 3"),
                    group=c("A","A","B","B"),
                    score=as.integer(c(20,10,15,5)),
                    stringsAsFactors=FALSE)
edges <- data.frame(source=c("node 0","node 0","node 0","node 2"),
                    target=c("node 1","node 2","node 3","node 3"),
                    interaction=c("inhibits","interacts","activates","interacts"),
                    weight=c(5.1,3.0,5.2,9.9),
                    stringsAsFactors=FALSE)

# Create an igraph object from the vignette's data frames.
# The workflow expects an object named 'ig' saved as 'ig.rds',
# which is a common convention for igraph objects.
ig <- graph_from_data_frame(d=edges, vertices=nodes, directed=TRUE)

# Serialize the 'ig' object to 'ig.rds' as required by the workflow.
saveRDS(ig, "ig.rds")