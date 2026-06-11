library(ExiMiR)

dir.create("Exiqon", showWarnings = FALSE, recursive = TRUE)

extdata_dir <- system.file("extdata", package="ExiMiR")

# 1. Targets.txt
targets_candidates <- list.files(extdata_dir, pattern = "Targets\\.txt$", recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
if (length(targets_candidates) > 0) {
    file.copy(targets_candidates[1], "Exiqon/Targets.txt", overwrite = TRUE)
} else {
    df_targets <- data.frame(
        FileName = "sample1.txt",
        Cy3 = "Sample",
        Cy5 = "Reference"
    )
    write.table(df_targets, "Exiqon/Targets.txt", sep="\t", row.names=FALSE, quote=FALSE)
}

# 2. Raw intensity .txt files
txt_candidates <- list.files(extdata_dir, pattern = "\\.txt$", recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
txt_candidates <- txt_candidates[!grepl("Targets\\.txt$", txt_candidates, ignore.case = TRUE)]
if (length(txt_candidates) > 0) {
    file.copy(txt_candidates, "Exiqon/", overwrite = TRUE)
} else {
    df_txt <- data.frame(
        `Gene ID` = "probe1",
        `Signal Mean` = 100,
        `Background Mean` = 10,
        check.names = FALSE
    )
    write.table(df_txt, "Exiqon/sample1.txt", sep="\t", row.names=FALSE, quote=FALSE)
}

# 3. GAL annotation file
gal_candidates <- list.files(extdata_dir, pattern = "\\.gal$", recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
if (length(gal_candidates) > 0) {
    file.copy(gal_candidates, "Exiqon/", overwrite = TRUE)
} else {
    gal_header <- c(
        "ATF\t1.0",
        "1\t2",
        "Type=GenePix ArrayList V1.0",
        "BlockCount=1",
        "Block1= 1, 1, 100, 1, 100, 1, 100",
        "Block\tRow\tColumn\tID\tName"
    )
    writeLines(gal_header, "Exiqon/annotation.gal")
    df_gal <- data.frame(
        Block = 1,
        Row = 1,
        Column = 1,
        ID = "probe1",
        Name = "probe1"
    )
    write.table(df_gal, "Exiqon/annotation.gal", sep="\t", row.names=FALSE, col.names=FALSE, quote=FALSE, append=TRUE)
}