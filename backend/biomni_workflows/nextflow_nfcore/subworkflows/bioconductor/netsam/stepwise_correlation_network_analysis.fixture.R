library(NetSAM)

# Prepare expression.cct
expr_file <- system.file("extdata", "exampleExpressionData.cct", package="NetSAM")
if (expr_file != "" && file.exists(expr_file)) {
    file.copy(expr_file, "expression.cct", overwrite = TRUE)
} else {
    expr_data <- data.frame(
        Sample1 = c(1.2, 2.3, 3.4, 4.5, 5.6),
        Sample2 = c(2.1, 3.2, 4.3, 5.4, 6.5),
        Sample3 = c(1.1, 2.2, 3.3, 4.4, 5.5),
        Sample4 = c(2.2, 3.3, 4.4, 5.5, 6.6)
    )
    rownames(expr_data) <- paste0("Gene", 1:5)
    write.table(expr_data, "expression.cct", sep="\t", quote=FALSE, row.names=TRUE, col.names=NA)
}

# Prepare sample_annotation.tsi
ann_file <- system.file("extdata", "sampleAnnotation.tsi", package="NetSAM")
if (ann_file != "" && file.exists(ann_file)) {
    file.copy(ann_file, "sample_annotation.tsi", overwrite = TRUE)
} else {
    ann_data <- data.frame(
        Feature = c("Type", "Category"),
        Sample1 = c("Tumor", "A"),
        Sample2 = c("Normal", "B"),
        Sample3 = c("Tumor", "A"),
        Sample4 = c("Normal", "B")
    )
    write.table(ann_data, "sample_annotation.tsi", sep="\t", quote=FALSE, row.names=FALSE)
}