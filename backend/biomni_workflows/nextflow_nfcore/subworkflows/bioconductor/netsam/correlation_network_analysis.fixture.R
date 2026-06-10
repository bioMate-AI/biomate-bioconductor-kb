library(NetSAM)

inputMatDir <- system.file("extdata", "exampleExpressionData.cct", package="NetSAM")
if (file.exists(inputMatDir)) {
    file.copy(inputMatDir, "exampleExpressionData.cct", overwrite = TRUE)
} else {
    # Fallback: create a synthetic exampleExpressionData.cct
    mat <- matrix(rnorm(100), nrow=10, ncol=10)
    rownames(mat) <- paste0("Gene", 1:10)
    colnames(mat) <- paste0("Sample", 1:10)
    write.table(mat, "exampleExpressionData.cct", sep="\t", quote=FALSE, col.names=NA)
}

sampleAnnDir <- system.file("extdata", "sampleAnnotation.tsi", package="NetSAM")
if (file.exists(sampleAnnDir)) {
    file.copy(sampleAnnDir, "sampleAnnotation.tsi", overwrite = TRUE)
} else {
    # Fallback: create a synthetic sampleAnnotation.tsi
    ann <- data.frame(
        Sample = paste0("Sample", 1:10),
        Feature1 = sample(c("A", "B"), 10, replace=TRUE),
        Feature2 = rnorm(10)
    )
    write.table(ann, "sampleAnnotation.tsi", sep="\t", quote=FALSE, row.names=FALSE)
}