suppressPackageStartupMessages({
    library(GOTHiC)
    library(HiCDataLymphoblast)
})

dirPath <- system.file("extdata", package = "HiCDataLymphoblast")
files <- list.files(dirPath, full.names = TRUE)

# The vignette uses the 4th file as the HiCUP output and the 3rd as the restriction file
if (length(files) >= 4) {
    file.copy(files[4], "fileName", overwrite = TRUE)
} else {
    # Fallback synthetic HiCUP output file
    hicup_dummy <- data.frame(
        Read1_Chr = "chr20", Read1_Start = 1000, Read1_Strand = "+",
        Read2_Chr = "chr20", Read2_Start = 2000, Read2_Strand = "-"
    )
    write.table(hicup_dummy, "fileName", sep = "\t", quote = FALSE, row.names = FALSE)
}

if (length(files) >= 3) {
    file.copy(files[3], "restrictionFile", overwrite = TRUE)
} else {
    # Fallback synthetic restriction fragment file
    res_dummy <- data.frame(
        Chromosome = "chr20", Start = 1, End = 5000, Fragment_ID = 1
    )
    write.table(res_dummy, "restrictionFile", sep = "\t", quote = FALSE, row.names = FALSE)
}