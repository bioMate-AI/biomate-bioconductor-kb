library(sitePath)
library(ape)

# Locate the example files shipped with the sitePath package
tree_src <- list.files(system.file("extdata", package = "sitePath"), pattern = "ZIKV.newick", full.names = TRUE)[1]
aln_src <- list.files(system.file("extdata", package = "sitePath"), pattern = "ZIKV.fasta", full.names = TRUE)[1]

# Copy the tree file to the expected input filename
if (!is.na(tree_src) && file.exists(tree_src)) {
    file.copy(tree_src, "tree_file", overwrite = TRUE)
} else {
    # Fallback synthetic tree if the package data is missing
    tree <- rcoal(10)
    write.tree(tree, "tree_file")
}

# Copy the alignment file to the expected input filename
if (!is.na(aln_src) && file.exists(aln_src)) {
    file.copy(aln_src, "alignment_file", overwrite = TRUE)
} else {
    # Fallback synthetic alignment if the package data is missing
    cat(">t1\nACGT\n>t2\nACGT\n", file = "alignment_file")
}