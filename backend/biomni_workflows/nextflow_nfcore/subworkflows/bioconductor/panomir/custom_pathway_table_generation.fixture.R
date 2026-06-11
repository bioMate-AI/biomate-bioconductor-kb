library(PanomiR)

# Load the pathway data from the package
data("msigdb_c2", package = "PanomiR")

# Serialize the pathway list to a GMT file
# GMT format: PathwayName \t Description \t Gene1 \t Gene2 ...
gmt_lines <- lapply(names(msigdb_c2), function(pw_name) {
    paste(c(pw_name, "PanomiR_pathway", msigdb_c2[[pw_name]]), collapse = "\t")
})

writeLines(unlist(gmt_lines), "pathways.gmt")