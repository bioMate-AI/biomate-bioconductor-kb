library(MungeSumstats)

# Locate the shipped example file
file_path <- system.file("extdata", "eduAttainOkbay.txt", package = "MungeSumstats")

# Copy it to the working directory as expected by the workflow
if (file.exists(file_path)) {
    file.copy(file_path, "eduAttainOkbay.txt", overwrite = TRUE)
} else {
    # Fallback: construct a synthetic GWAS summary statistics file if the shipped file is missing
    synth_data <- data.frame(
        MarkerName = c("rs3131972", "rs3131969", "rs3131967"),
        CHR = c(6, 6, 6),
        POS = c(3212236, 3212237, 3212238),
        A1 = c("A", "G", "T"),
        A2 = c("G", "C", "C"),
        Pval = c(0.04, 0.01, 0.05),
        Beta = c(0.12, -0.05, 0.08),
        SE = c(0.01, 0.02, 0.01)
    )
    write.table(synth_data, "eduAttainOkbay.txt", sep = "\t", row.names = FALSE, quote = FALSE)
}