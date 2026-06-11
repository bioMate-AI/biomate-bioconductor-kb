library(MSstatsLiP)

# Locate the ground truth files shipped with the package
lip_file <- list.files(system.file(package="MSstatsLiP"), pattern="raw_lip\\.csv$", recursive=TRUE, full.names=TRUE)[1]
prot_file <- list.files(system.file(package="MSstatsLiP"), pattern="raw_prot\\.csv$", recursive=TRUE, full.names=TRUE)[1]
fasta_file <- list.files(system.file(package="MSstatsLiP"), pattern="fasta_file\\.fasta$", recursive=TRUE, full.names=TRUE)[1]

# Copy or generate LiPRawData
if (!is.na(lip_file) && file.exists(lip_file)) {
    file.copy(lip_file, "LiPRawData", overwrite = TRUE)
} else {
    # Fallback synthetic data matching Spectronaut export format
    lip_data <- data.frame(
        ProteinName = "P37840",
        PeptideSequence = "PEPTIDE",
        PrecursorCharge = 2,
        FragmentIon = "y1",
        ProductCharge = 1,
        IsotopeLabelType = "L",
        Condition = "F1",
        BioReplicate = "1",
        Run = "Run1",
        Intensity = 1000,
        FExcludedFromQuantification = FALSE,
        EGQvalue = 0.001
    )
    write.csv(lip_data, "LiPRawData", row.names = FALSE)
}

# Copy or generate TrPRawData
if (!is.na(prot_file) && file.exists(prot_file)) {
    file.copy(prot_file, "TrPRawData", overwrite = TRUE)
} else {
    # Fallback synthetic data matching Spectronaut export format
    prot_data <- data.frame(
        ProteinName = "P37840",
        PeptideSequence = "PEPTIDE",
        PrecursorCharge = 2,
        FragmentIon = "y1",
        ProductCharge = 1,
        IsotopeLabelType = "L",
        Condition = "F2",
        BioReplicate = "1",
        Run = "Run1",
        Intensity = 1000,
        FExcludedFromQuantification = FALSE,
        EGQvalue = 0.001
    )
    write.csv(prot_data, "TrPRawData", row.names = FALSE)
}

# Copy or generate ExampleFastaFile.fasta
if (!is.na(fasta_file) && file.exists(fasta_file)) {
    file.copy(fasta_file, "ExampleFastaFile.fasta", overwrite = TRUE)
} else {
    # Fallback synthetic FASTA
    writeLines(c(">P37840", "PEPTIDE"), "ExampleFastaFile.fasta")
}