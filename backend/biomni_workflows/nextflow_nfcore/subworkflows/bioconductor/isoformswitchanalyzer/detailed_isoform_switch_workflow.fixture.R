library(IsoformSwitchAnalyzeR)

# 1. Serialize the switchAnalyzeRlist object
data("exampleSwitchList", package = "IsoformSwitchAnalyzeR")
saveRDS(exampleSwitchList, file = "switchAnalyzeRlist")

# 2. Provide external_results (output files from CPAT, CPC2, Pfam, SignalP, etc.)
dir.create("external_results", showWarnings = FALSE)
extdata_dir <- system.file("extdata", package = "IsoformSwitchAnalyzeR")
ext_files <- list.files(extdata_dir, full.names = TRUE)

if (length(ext_files) > 0) {
    file.copy(ext_files, "external_results/")
} else {
    # Fallback synthetic file if extdata is missing
    write.table(
        data.frame(Sequence = "seq1", Coding_Probability = 0.9), 
        file = "external_results/cpat_dummy.txt", 
        sep = "\t", 
        row.names = FALSE
    )
}