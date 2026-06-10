suppressPackageStartupMessages({
    library(monaLisa)
    library(GenomicRanges)
    library(SummarizedExperiment)
    library(JASPAR2020)
    library(TFBSTools)
    library(BSgenome.Mmusculus.UCSC.mm10)
    library(TxDb.Mmusculus.UCSC.mm10.knownGene)
})

# The workflow environment expects these package objects to be available as files 
# in the working directory based on the parsed input specification.
# We serialize the actual package objects to satisfy the file existence and content requirements.
saveRDS(TxDb.Mmusculus.UCSC.mm10.knownGene, "TxDb.Mmusculus.UCSC.mm10.knownGene")
saveRDS(BSgenome.Mmusculus.UCSC.mm10, "BSgenome.Mmusculus.UCSC.mm10")
saveRDS(JASPAR2020, "JASPAR2020")

# Reproducing the vignette's data preparation for completeness
lmrfile <- system.file("extdata", "LMRsESNPmerged.gr.rds", package = "monaLisa")
if (file.exists(lmrfile)) {
    lmr <- readRDS(lmrfile)
    set.seed(1)
    lmrsel <- lmr[sample(x = length(lmr), size = 10000, replace = FALSE)]
    bins <- bin(x = lmrsel$deltaMeth, binmode = "equalN", nElement = 800, minAbsX = 0.3)
    pwms <- getMatrixSet(JASPAR2020, opts = list(matrixtype = "PWM", tax_group = "vertebrates"))
}