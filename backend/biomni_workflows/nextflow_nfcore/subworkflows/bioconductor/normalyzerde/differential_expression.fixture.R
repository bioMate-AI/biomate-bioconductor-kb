library(NormalyzerDE)

# Locate the built-in datasets from the package
designFp <- system.file("extdata", "tiny_design.tsv", package="NormalyzerDE")
dataFp <- system.file("extdata", "tiny_data.tsv", package="NormalyzerDE")

# 1. Provide tiny_design.tsv in the working directory
if (file.exists(designFp)) {
    file.copy(designFp, "tiny_design.tsv", overwrite = TRUE)
} else {
    # Fallback if the file is missing from the installation
    design_data <- data.frame(
        sample = c("s_125amol_1", "s_125amol_2", "s_125amol_3", "s_12500amol_1", "s_12500amol_2", "s_12500amol_3"),
        group = c("125amol", "125amol", "125amol", "12500amol", "12500amol", "12500amol"),
        batch = c(1, 1, 1, 2, 2, 2)
    )
    write.table(design_data, "tiny_design.tsv", sep="\t", row.names=FALSE, quote=FALSE)
    designFp <- "tiny_design.tsv"
}

# 2. Generate CycLoess-normalized.txt using the package's evaluation workflow
outDir <- tempdir()

# Run the normalyzer evaluation which generates the normalized matrices
if (file.exists(dataFp) && file.exists(designFp)) {
    suppressWarnings({
        normalyzer(
            jobName = "vignette_run", 
            designPath = designFp, 
            dataPath = dataFp, 
            outputDir = outDir
        )
    })
}

normMatrixPath <- file.path(outDir, "vignette_run", "CycLoess-normalized.txt")

# Copy the generated normalized matrix to the working directory
if (file.exists(normMatrixPath)) {
    file.copy(normMatrixPath, "CycLoess-normalized.txt", overwrite = TRUE)
} else {
    # Fallback: manually perform the cyclic loess normalization if the wrapper failed
    fullDf <- read.table(dataFp, sep="\t", header=TRUE, stringsAsFactors=FALSE)
    designDf <- read.table(designFp, sep="\t", header=TRUE, stringsAsFactors=FALSE)
    
    sampleNames <- as.character(designDf$sample)
    dataMat <- as.matrix(fullDf[, sampleNames])
    
    # Perform Cyclic Loess Normalization
    log2Matrix <- log2(dataMat)
    normMatrix <- limma::normalizeCyclicLoess(log2Matrix, method="fast")
    colnames(normMatrix) <- colnames(dataMat)
    
    # Combine annotations with normalized data
    annotOnly <- fullDf[, !(colnames(fullDf) %in% sampleNames), drop=FALSE]
    outDf <- cbind(annotOnly, normMatrix)
    
    write.table(outDf, "CycLoess-normalized.txt", sep="\t", row.names=FALSE, quote=FALSE)
}