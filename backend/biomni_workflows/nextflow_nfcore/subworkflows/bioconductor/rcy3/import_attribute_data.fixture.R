# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("RCy3")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(RCy3)

# --- Data preparation for network_file.sif ---
# This data comes from section 4 "My first network" of the RCy3 vignette.
nodes_vignette <- data.frame(id=c("node 0","node 1","node 2","node 3"),
                             group=c("A","A","B","B"),
                             score=as.integer(c(20,10,15,5)),
                             stringsAsFactors=FALSE)
edges_vignette <- data.frame(source=c("node 0","node 0","node 0","node 2"),
                             target=c("node 1","node 2","node 3","node 3"),
                             interaction=c("inhibits","interacts","activates","interacts"),
                             weight=c(5.1,3.0,5.2,9.9),
                             stringsAsFactors=FALSE)

# Construct SIF content from the edges data frame.
# A SIF file typically has lines like: nodeA <interaction type> nodeB.
sif_content <- paste(edges_vignette$source, edges_vignette$interaction, edges_vignette$target, sep = " ")

# Write the SIF content to network_file.sif
writeLines(sif_content, "network_file.sif")

# --- Data preparation for expression_data.csv ---
# This data comes from section 5.1 "Add node attributes" of the RCy3 vignette.
df_vignette <- data.frame (moleculeType=c('kinase','TF','cytokine','cytokine'),
                           log2fc=c(1.8,3.0,-1.2,-2.5),
                           row.names = c('A','B','C','D'), # These are the node names
                           stringsAsFactors = FALSE)

# The workflow reads this CSV and uses loadTableData(data, data.key.column="name").
# Therefore, the CSV needs a column explicitly named "name" that contains the node identifiers.
# The row.names of df_vignette serve as these node identifiers.
expression_data <- data.frame(name = row.names(df_vignette), df_vignette, stringsAsFactors = FALSE)
# Remove original row names from the data frame to prevent write.csv from adding an unnamed column.
row.names(expression_data) <- NULL

# Write the data frame to expression_data.csv.
# Ensure row.names are not written as a separate column, as we already have 'name'.
write.csv(expression_data, "expression_data.csv", row.names = FALSE)