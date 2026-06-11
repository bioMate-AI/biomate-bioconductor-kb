# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BioNet", "DLBCL")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BioNet)
library(DLBCL)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code

# Load the interactome object from the DLBCL package
data(interactome)

# Load dataLym object from the DLBCL package
data(dataLym)

# Prepare the pvals_matrix object as shown in the vignette (chunk 3)
pvals_matrix <- cbind(t=dataLym$t.pval, s=dataLym$s.pval)
rownames(pvals_matrix) <- dataLym$label

# 2. Serialize objects to input files in the exact format the workflow reads

# Save pvals_matrix to "pvals_matrix.txt"
# The workflow reads this with read.table("pvals_matrix.txt", header=TRUE, sep="\t", row.names=1, check.names=FALSE)
# write.table with col.names=NA ensures the first column is row names, and subsequent columns are data.
# quote=FALSE prevents quoting of character strings.
write.table(pvals_matrix, "pvals_matrix.txt", sep="\t", quote=FALSE, col.names=NA)

# Save interactome (a graphNEL object) to "ppi_network.sif"
# A SIF (Simple Interaction Format) file is typically a tab-separated file
# with lines like: node1 <interaction_type> node2.
# BioNet's loadNetwork.sif expects this format.
sif_lines <- character()
for (node_u in nodes(interactome)) {
    # Iterate through all outgoing edges from node_u
    if (length(edges(interactome)[[node_u]]) > 0) {
        for (node_v in edges(interactome)[[node_u]]) {
            # Use "-" as a generic interaction type, which is commonly accepted by SIF readers
            sif_lines <- c(sif_lines, paste(node_u, "-", node_v, sep="\t"))
        }
    }
}
writeLines(sif_lines, "ppi_network.sif")