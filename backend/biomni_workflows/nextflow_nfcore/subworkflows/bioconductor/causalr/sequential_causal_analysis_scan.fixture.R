library(CausalR)

sif_file <- system.file("extdata", "testNetwork1.sif", package="CausalR")
if (file.exists(sif_file)) {
    file.copy(sif_file, "testNetwork1.sif", overwrite = TRUE)
} else {
    writeLines(c(
        "Node0\tActivates\tNode1",
        "Node0\tInhibits\tNode2",
        "Node1\tActivates\tNode3",
        "Node2\tActivates\tNode3"
    ), "testNetwork1.sif")
}

data_file <- system.file("extdata", "testData1.txt", package="CausalR")
if (file.exists(data_file)) {
    file.copy(data_file, "testData1.txt", overwrite = TRUE)
} else {
    writeLines(c(
        "Node0\t1",
        "Node1\t1",
        "Node2\t-1",
        "Node3\t1"
    ), "testData1.txt")
}