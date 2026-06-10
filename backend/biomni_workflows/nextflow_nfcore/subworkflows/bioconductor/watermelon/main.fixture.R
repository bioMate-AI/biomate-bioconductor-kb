library(wateRmelon)

# 1. Create the directory for IDAT files
dir.create("path/to/idats", recursive = TRUE, showWarnings = FALSE)

# 2. Find IDAT files from common methylation data packages
idat_files <- character(0)
for (pkg in c("minfiDataEPIC", "minfiData", "methylumi", "wateRmelon")) {
    if (requireNamespace(pkg, quietly = TRUE)) {
        files <- list.files(system.file("extdata", package = pkg), pattern = "\\.idat(\\.gz)?$", recursive = TRUE, full.names = TRUE)
        if (length(files) > 0) {
            idat_files <- files
            break
        }
    }
}

# Copy found IDAT files to the target directory
if (length(idat_files) > 0) {
    for (f in idat_files) {
        file.copy(f, file.path("path/to/idats", basename(f)))
    }
    
    # Extract basenames for phenotype data
    basenames <- unique(gsub("_(Grn|Red)\\.idat(\\.gz)?$", "", basename(idat_files)))
    
    pheno <- data.frame(
        Basename = basenames,
        Sample_Name = paste0("Sample_", seq_along(basenames)),
        Age = sample(20:60, length(basenames), replace = TRUE),
        Sex = sample(c("M", "F"), length(basenames), replace = TRUE),
        stringsAsFactors = FALSE
    )
} else {
    # Fallback if no IDAT files are found (to ensure files exist)
    dummy_basenames <- c("dummy1", "dummy2")
    for (b in dummy_basenames) {
        writeBin(raw(0), file.path("path/to/idats", paste0(b, "_Grn.idat")))
        writeBin(raw(0), file.path("path/to/idats", paste0(b, "_Red.idat")))
    }
    pheno <- data.frame(
        Basename = dummy_basenames,
        Sample_Name = c("Sample_1", "Sample_2"),
        Age = c(30, 45),
        Sex = c("M", "F"),
        stringsAsFactors = FALSE
    )
}

# 3. Write the phenotype data
write.csv(pheno, "pheno_data", row.names = FALSE)