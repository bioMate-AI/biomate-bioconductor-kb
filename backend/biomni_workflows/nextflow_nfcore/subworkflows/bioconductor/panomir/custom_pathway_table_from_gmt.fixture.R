library(PanomiR)

data("msigdb_c2", package = "PanomiR")

# Convert the list of pathways into GMT format
# GMT format: Pathway_Name \t Description \t Gene1 \t Gene2 \t ...
gmt_lines <- sapply(names(msigdb_c2), function(pw_name) {
    genes <- msigdb_c2[[pw_name]]
    paste(c(pw_name, "PanomiR_msigdb_c2", genes), collapse = "\t")
})

writeLines(gmt_lines, "pathways.gmt")