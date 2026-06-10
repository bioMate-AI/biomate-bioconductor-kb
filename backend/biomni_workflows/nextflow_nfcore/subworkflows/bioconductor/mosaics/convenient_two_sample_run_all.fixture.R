suppressPackageStartupMessages({
    library(mosaics)
})

# The workflow expects these two files in the working directory.
# We search for them in the installed package's extdata directory.
chip_candidates <- list.files(system.file("extdata", package="mosaics"), 
                              pattern="STAT1_ChIP_eland_results.txt", 
                              recursive=TRUE, full.names=TRUE)

control_candidates <- list.files(system.file("extdata", package="mosaics"), 
                                 pattern="STAT1_control_eland_results.txt", 
                                 recursive=TRUE, full.names=TRUE)

# If mosaicsExample is available, check there as well
if (requireNamespace("mosaicsExample", quietly = TRUE)) {
    chip_candidates <- c(chip_candidates, 
                         list.files(system.file("extdata", package="mosaicsExample"), 
                                    pattern="STAT1_ChIP_eland_results.txt", 
                                    recursive=TRUE, full.names=TRUE))
    control_candidates <- c(control_candidates, 
                            list.files(system.file("extdata", package="mosaicsExample"), 
                                       pattern="STAT1_control_eland_results.txt", 
                                       recursive=TRUE, full.names=TRUE))
}

# Copy or synthesize the ChIP file
if (length(chip_candidates) > 0 && file.exists(chip_candidates[1])) {
    file.copy(chip_candidates[1], "STAT1_ChIP_eland_results.txt", overwrite=TRUE)
} else {
    # Synthesize a minimal eland_result format file if not found
    writeLines(c(
        ">EAS54_61:4:1:20:213\tTGCGGCTGCCAGAT\tU0\t1\t0\t0\tchr22\t1000000\tF\t..",
        ">EAS54_61:4:1:20:214\tTGCGGCTGCCAGAT\tU0\t1\t0\t0\tchr22\t1000200\tF\t.."
    ), "STAT1_ChIP_eland_results.txt")
}

# Copy or synthesize the Control file
if (length(control_candidates) > 0 && file.exists(control_candidates[1])) {
    file.copy(control_candidates[1], "STAT1_control_eland_results.txt", overwrite=TRUE)
} else {
    # Synthesize a minimal eland_result format file if not found
    writeLines(c(
        ">EAS54_61:4:1:20:215\tTGCGGCTGCCAGAT\tU0\t1\t0\t0\tchr22\t1000000\tF\t..",
        ">EAS54_61:4:1:20:216\tTGCGGCTGCCAGAT\tU0\t1\t0\t0\tchr22\t1000500\tF\t.."
    ), "STAT1_control_eland_results.txt")
}