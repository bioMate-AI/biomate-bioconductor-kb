library(MOGAMUN)

# 1. Sample_DE.csv
dePath <- system.file("extdata/DE/Sample_DE.csv", package = "MOGAMUN")
if (file.exists(dePath)) {
    file.copy(dePath, "Sample_DE.csv", overwrite = TRUE)
} else {
    df_de <- data.frame(
        gene = c("GeneA", "GeneB", "GeneC", "GeneD"), 
        FDR = c(0.01, 0.04, 0.1, 0.005), 
        logFC = c(1.5, -2.0, 0.5, 3.1)
    )
    write.csv(df_de, "Sample_DE.csv", row.names = FALSE)
}

# 2. Sample_NodesScore.csv
scoresPath <- system.file("extdata/DE/Sample_NodesScore.csv", package = "MOGAMUN")
if (file.exists(scoresPath)) {
    file.copy(scoresPath, "Sample_NodesScore.csv", overwrite = TRUE)
} else {
    df_scores <- data.frame(
        gene = c("GeneA", "GeneB", "GeneC", "GeneD"), 
        score = c(2.5, 1.8, 0.9, 3.5)
    )
    write.csv(df_scores, "Sample_NodesScore.csv", row.names = FALSE)
}

# 3. NetworkLayersDir
layersPath <- system.file("extdata/LayersMultiplex", package = "MOGAMUN")
dir.create("NetworkLayersDir", showWarnings = FALSE)
if (dir.exists(layersPath) && length(list.files(layersPath)) > 0) {
    file.copy(list.files(layersPath, full.names = TRUE), "NetworkLayersDir/", overwrite = TRUE)
} else {
    write.table(
        data.frame(V1 = c("GeneA", "GeneB"), V2 = c("GeneB", "GeneC")), 
        "NetworkLayersDir/1_network.txt", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE
    )
    write.table(
        data.frame(V1 = c("GeneA", "GeneC"), V2 = c("GeneC", "GeneD")), 
        "NetworkLayersDir/2_network.txt", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE
    )
    write.table(
        data.frame(V1 = c("GeneB", "GeneD"), V2 = c("GeneC", "GeneA")), 
        "NetworkLayersDir/3_network.txt", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE
    )
}