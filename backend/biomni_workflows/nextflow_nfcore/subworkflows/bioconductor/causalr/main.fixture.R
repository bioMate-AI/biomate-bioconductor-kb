library(CausalR)

# Find and copy testNetwork1.sif
sif_file <- list.files(system.file(package="CausalR"), pattern="testNetwork1\\.sif$", recursive=TRUE, full.names=TRUE)
if (length(sif_file) > 0) {
    file.copy(sif_file[1], "testNetwork1.sif", overwrite = TRUE)
} else {
    # Fallback synthetic SIF
    sif_content <- c(
        "Node0\tActivates\tNode1",
        "Node0\tInhibits\tNode2",
        "Node1\tActivates\tNode3",
        "Node2\tActivates\tNode3"
    )
    writeLines(sif_content, "testNetwork1.sif")
}

# Find and copy testData1.txt
txt_file <- list.files(system.file(package="CausalR"), pattern="testData1\\.txt$", recursive=TRUE, full.names=TRUE)
if (length(txt_file) > 0) {
    file.copy(txt_file[1], "testData1.txt", overwrite = TRUE)
} else {
    # Fallback synthetic data
    txt_content <- c(
        "Node0\t1",
        "Node1\t1",
        "Node2\t-1",
        "Node3\t1"
    )
    writeLines(txt_content, "testData1.txt")
}