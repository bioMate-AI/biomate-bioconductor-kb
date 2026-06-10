suppressPackageStartupMessages(library(DiffBind))

extra_dir <- system.file("extra", package="DiffBind")
samples <- read.csv(file.path(extra_dir, "tamoxifen.csv"), stringsAsFactors=FALSE)

# Copy all referenced BAM and BED/Peak files to the current working directory
for (col in c("bamReads", "bamControl", "Peaks")) {
    if (col %in% colnames(samples)) {
        for (f in samples[[col]]) {
            if (!is.na(f) && f != "") {
                d <- dirname(f)
                if (d != "." && !dir.exists(d)) {
                    dir.create(d, recursive = TRUE, showWarnings = FALSE)
                }
                src <- file.path(extra_dir, f)
                if (file.exists(src)) {
                    file.copy(src, f, overwrite = TRUE)
                    # Copy BAM indices if they exist
                    if (grepl("\\.bam$", f)) {
                        bai1 <- paste0(src, ".bai")
                        if (file.exists(bai1)) file.copy(bai1, paste0(f, ".bai"), overwrite = TRUE)
                        bai2 <- sub("\\.bam$", ".bai", src)
                        if (file.exists(bai2)) file.copy(bai2, sub("\\.bam$", ".bai", f), overwrite = TRUE)
                    }
                } else {
                    # Fallback to create dummy files if missing from the installation
                    if (grepl("\\.bam$", f)) {
                        file.create(f)
                    } else if (grepl("\\.bed\\.gz$", f)) {
                        gz <- gzfile(f, "w")
                        writeLines(c("chr18\t100\t200\tpeak1\t10", "chr18\t300\t400\tpeak2\t20"), gz)
                        close(gz)
                    } else {
                        file.create(f)
                    }
                }
            }
        }
    }
}

# Write the sample sheet to the current working directory
write.csv(samples, "tamoxifen.csv", row.names = FALSE)