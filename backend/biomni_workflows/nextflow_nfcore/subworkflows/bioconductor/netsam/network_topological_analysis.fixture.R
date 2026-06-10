library(NetSAM)

input_file <- system.file("extdata", "exampleNetwork.net", package="NetSAM")
if (file.exists(input_file)) {
    file.copy(input_file, "exampleNetwork.net", overwrite = TRUE)
} else {
    # Fallback: create a small synthetic edge-list file
    edges <- data.frame(
        Node1 = c("GeneA", "GeneA", "GeneB", "GeneC", "GeneD", "GeneE"),
        Node2 = c("GeneB", "GeneC", "GeneC", "GeneD", "GeneE", "GeneA")
    )
    write.table(edges, "exampleNetwork.net", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
}