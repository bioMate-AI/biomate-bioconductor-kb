library(TEQC)

exptPath <- system.file("extdata", package = "TEQC")

targets_src <- file.path(exptPath, "ExampleSet_Targets.bed")
if (file.exists(targets_src)) {
    file.copy(targets_src, "ExampleSet_Targets.bed", overwrite = TRUE)
} else {
    # Fallback if not found
    write.table(
        data.frame(chr = "chr1", start = 11157524, end = 11158764),
        "ExampleSet_Targets.bed",
        sep = "\t",
        row.names = FALSE,
        col.names = FALSE,
        quote = FALSE
    )
}

reads_src <- file.path(exptPath, "ExampleSet_Reads.bed")
if (file.exists(reads_src)) {
    file.copy(reads_src, "ExampleSet_Reads.bed", overwrite = TRUE)
} else {
    # Fallback if not found
    write.table(
        data.frame(chr = "chr1", start = 11157524, end = 11157560, id = "read1"),
        "ExampleSet_Reads.bed",
        sep = "\t",
        row.names = FALSE,
        col.names = FALSE,
        quote = FALSE
    )
}