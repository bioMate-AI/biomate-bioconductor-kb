# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("philr", "ape", "mia", "dplyr")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(philr)
library(ape)
library(mia)
library(dplyr)

# Load the GlobalPatterns dataset from the mia package
data(GlobalPatterns, package = "mia")

# Filter Extremely Low-Abundance OTUs
tse <- GlobalPatterns %>% subsetByPrevalentTaxa(
    detection = 3, prevalence = 20/100, as_relative = FALSE)

# Pick taxa that have notable abundance variation across samples
variable.taxa <- apply(assays(tse)$counts, 1, function(x) sd(x)/mean(x) > 3.0)
tse <- tse[variable.taxa,]

# Collapse the tree
tree <- ape::keep.tip(phy = rowTree(tse), tip = rowLinks(tse)$nodeNum)
rowTree(tse) <- tree

# Add a new assay with a pseudocount
assays(tse)$counts.shifted <- assays(tse)$counts + 1

# Process Phylogenetic Tree
tree <- makeNodeLabel(tree, method="number", prefix='n')
rowTree(tse) <- tree

# Extract components
otu.table <- as.matrix(assays(tse)$counts)
tree <- rowTree(tse)
metadata <- colData(tse)
tax <- rowData(tse)[, taxonomyRanks(tse)]

# Write the extracted components to the required input files
write.table(otu.table, file = "otu_table.tsv", sep = "\t", quote = FALSE, col.names = NA)
ape::write.tree(tree, file = "phylo_tree.tre")
write.table(as.data.frame(tax), file = "taxonomy.tsv", sep = "\t", quote = FALSE, col.names = NA)
write.table(as.data.frame(metadata), file = "metadata.tsv", sep = "\t", quote = FALSE, col.names = NA)