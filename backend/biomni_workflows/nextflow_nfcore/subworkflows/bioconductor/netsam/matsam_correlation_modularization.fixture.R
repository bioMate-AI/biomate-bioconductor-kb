library(NetSAM)

# Attempt to use the package's provided example expression file
cct_file <- system.file("extdata", "exampleExpressionData.cct", package="NetSAM")
if (file.exists(cct_file) && file.info(cct_file)$size > 0) {
    file.copy(cct_file, "expression.cct", overwrite = TRUE)
} else {
    # Fallback to synthetic expression data matching the required format
    expr_data <- data.frame(
        GeneID = paste0("Gene", 1:10),
        Sample1 = runif(10, 1, 10),
        Sample2 = runif(10, 1, 10),
        Sample3 = runif(10, 1, 10),
        Sample4 = runif(10, 1, 10),
        stringsAsFactors = FALSE
    )
    write.table(expr_data, "expression.cct", sep="\t", row.names=FALSE, quote=FALSE)
}

# Attempt to use the package's provided example sample annotation file
tsi_file <- system.file("extdata", "sampleAnnotation.tsi", package="NetSAM")
if (file.exists(tsi_file) && file.info(tsi_file)$size > 0) {
    file.copy(tsi_file, "sample_annotation.tsi", overwrite = TRUE)
} else {
    # Fallback to synthetic sample annotation data matching the required format
    tsi_data <- data.frame(
        Feature = c("Gender", "Age"),
        Type = c("Categorical", "Continuous"),
        Sample1 = c("M", "50"),
        Sample2 = c("F", "60"),
        Sample3 = c("M", "45"),
        Sample4 = c("F", "55"),
        stringsAsFactors = FALSE
    )
    write.table(tsi_data, "sample_annotation.tsi", sep="\t", row.names=FALSE, quote=FALSE)
}