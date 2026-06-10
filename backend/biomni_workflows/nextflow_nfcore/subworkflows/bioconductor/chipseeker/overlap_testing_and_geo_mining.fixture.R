suppressPackageStartupMessages({
    library(ChIPseeker)
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
})

# Prepare the TxDb object as used in the vignette
txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene

# The workflow excerpt reads "txdb.rds"
saveRDS(txdb, "txdb.rds")
# Also save to literal "txdb" to satisfy the exact declared input name requirement
saveRDS(txdb, "txdb")

# The vignette uses getSampleFiles() to get a list of BED files
files <- getSampleFiles()

# The parser extracted literal strings "files[[5]]" and "files[1:4]" as file names.
# We copy actual sample BED files to these literal filenames to guarantee they exist 
# and contain valid BED data for readPeakFile().
if (length(files) >= 5) {
    file.copy(files[[5]], "files[[5]]", overwrite = TRUE)
}

if (length(files) >= 1) {
    file.copy(files[[1]], "files[1:4]", overwrite = TRUE)
}