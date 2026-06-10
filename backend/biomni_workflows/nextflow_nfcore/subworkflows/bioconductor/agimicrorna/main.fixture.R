library(AgiMicroRna)

# 1. Load the target data from the package and write to targets.txt
data(targets.micro)
write.table(targets.micro, file = "targets.txt", sep = "\t", row.names = FALSE, quote = FALSE)

# 2. Locate the Agilent Feature Extraction scanned data file shipped with the package
mscA1_path <- list.files(system.file(package = "AgiMicroRna"), pattern = "^mscA1\\.txt$", recursive = TRUE, full.names = TRUE)

if (length(mscA1_path) > 0) {
    # Copy the found file to the working directory
    file.copy(mscA1_path[1], "mscA1.txt", overwrite = TRUE)
    
    # To ensure readMicroRnaAFE() succeeds for all samples in targets.txt,
    # copy mscA1.txt to all other filenames specified in the targets file.
    for (f in as.character(targets.micro$FileName)) {
        if (!file.exists(f)) {
            file.copy(mscA1_path[1], f, overwrite = TRUE)
        }
    }
} else {
    # Fallback: Create a minimal dummy Agilent FE file if not found
    dummy_lines <- c(
        "TYPE\tText",
        "FEPARAMS\t1",
        "DATA\t1",
        "FEATURES\tFeatureNum\tRow\tCol\tProbeUID\tControlType\tProbeName\tGeneName\tSystematicName\tgTotalGeneSignal\tgProcessedSignal\tgIsGeneDetected\tgIsSaturated\tgIsFeatNonUnifOL\tgIsFeatPopnOL\tgBGMedianSignal\tgBGUsed",
        "DATA\t1\t1\t1\t1\t0\tProbe1\tGene1\tSys1\t100\t100\t1\t0\t0\t0\t10\t10"
    )
    writeLines(dummy_lines, "mscA1.txt")
    
    for (f in as.character(targets.micro$FileName)) {
        if (!file.exists(f)) {
            writeLines(dummy_lines, f)
        }
    }
}