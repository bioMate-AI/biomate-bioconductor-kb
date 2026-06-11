library(BCRANK)

# Locate the example FASTA file shipped with the package
src_fasta <- system.file("Exfiles/USF1_small.fa", package="BCRANK")

# Fallback to finding any .fa file in the package if the exact path changed
if (!file.exists(src_fasta)) {
    src_fasta <- list.files(system.file(package="BCRANK"), pattern="\\.fa$", recursive=TRUE, full.names=TRUE)[1]
}

# Copy the file to the working directory to satisfy the expected input file names
if (length(src_fasta) > 0 && !is.na(src_fasta) && file.exists(src_fasta)) {
    file.copy(src_fasta, "fastaFile", overwrite = TRUE)
    file.copy(src_fasta, "fastaFile.fa", overwrite = TRUE)
} else {
    # Fallback: create a synthetic FASTA file if no package data is found
    dummy_fasta <- c(
        ">region1",
        "GTCACGTGGTCACGTG",
        ">region2",
        "CACGTGACCACGTGAC",
        ">region3",
        "CGCGGACGCGGA"
    )
    writeLines(dummy_fasta, "fastaFile")
    writeLines(dummy_fasta, "fastaFile.fa")
}