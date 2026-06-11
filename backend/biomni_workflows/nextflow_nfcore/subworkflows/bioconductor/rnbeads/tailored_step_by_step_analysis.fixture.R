suppressPackageStartupMessages(library(RnBeads))

# Create the required idat directory
dir.create("idat", showWarnings = FALSE)

idat_copied <- FALSE

# Attempt to use real idat files from minfiData if available, 
# as RnBeads requires valid idat files for import
if (requireNamespace("minfiData", quietly = TRUE)) {
    minfi_dir <- system.file("extdata", "5723646052", package = "minfiData")
    if (nzchar(minfi_dir) && dir.exists(minfi_dir)) {
        idat_files <- list.files(minfi_dir, pattern = "\\.idat$", full.names = TRUE)
        if (length(idat_files) > 0) {
            file.copy(idat_files, "idat/")
            
            # Extract basenames to construct a matching sample annotation
            basenames <- unique(gsub("_(Grn|Red)\\.idat$", "", basename(idat_files)))
            
            annot <- data.frame(
                Sample_ID = paste0("Sample_", seq_along(basenames)),
                Sentrix_ID = sapply(strsplit(basenames, "_"), `[`, 1),
                Sentrix_Position = sapply(strsplit(basenames, "_"), `[`, 2),
                Sample_Group = rep(c("Control", "Treatment"), length.out = length(basenames)),
                stringsAsFactors = FALSE
            )
            write.csv(annot, "sample_annotation.csv", row.names = FALSE)
            idat_copied <- TRUE
        }
    }
}

# Fallback to synthetic files if minfiData is not available
if (!idat_copied) {
    dummy_basenames <- c("5723646052_R02C02", "5723646052_R04C01")
    
    # Create dummy binary idat files
    for (bn in dummy_basenames) {
        writeBin(as.raw(1:10), file.path("idat", paste0(bn, "_Grn.idat")))
        writeBin(as.raw(1:10), file.path("idat", paste0(bn, "_Red.idat")))
    }
    
    # Create matching sample annotation
    annot <- data.frame(
        Sample_ID = c("Sample_1", "Sample_2"),
        Sentrix_ID = c("5723646052", "5723646052"),
        Sentrix_Position = c("R02C02", "R04C01"),
        Sample_Group = c("Control", "Treatment"),
        stringsAsFactors = FALSE
    )
    write.csv(annot, "sample_annotation.csv", row.names = FALSE)
}