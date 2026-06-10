library(R453Plus1Toolbox)

# Create the required output directory
dir.create("mapping", showWarnings = FALSE, recursive = TRUE)

# Locate and copy 454HCDiffs.txt
hc_diffs_files <- list.files(system.file("extdata", package="R453Plus1Toolbox"), 
                             pattern="454HCDiffs.txt", recursive=TRUE, full.names=TRUE)
if (length(hc_diffs_files) > 0) {
    file.copy(hc_diffs_files[1], "mapping/454HCDiffs.txt", overwrite = TRUE)
} else {
    # Fallback dummy if not found
    writeLines(c("Accno\tStart\tEnd\tRef\tVar\tTotalDepth\tVarFreq"), "mapping/454HCDiffs.txt")
}

# Locate and copy 454NewblerMetrics.txt
metrics_files <- list.files(system.file("extdata", package="R453Plus1Toolbox"), 
                            pattern="454NewblerMetrics.txt", recursive=TRUE, full.names=TRUE)
if (length(metrics_files) > 0) {
    file.copy(metrics_files[1], "mapping/454NewblerMetrics.txt", overwrite = TRUE)
} else {
    # Fallback dummy if not found
    writeLines(c("Metric\tValue"), "mapping/454NewblerMetrics.txt")
}