suppressPackageStartupMessages({
    library(MAGAR)
})

# 1. Create idat_dir and populate with methylation IDAT files
dir.create("idat_dir", showWarnings = FALSE)
sample_ids <- c("Sample_1", "Sample_2", "Sample_3")
barcodes <- c("209054857842_R01C01", "209054857842_R02C01", "209054857842_R03C01")

# Try to use real IDAT files from minfiData if available
if (requireNamespace("minfiData", quietly = TRUE)) {
    baseDir <- system.file("extdata", "5723646052", package="minfiData")
    if (nzchar(baseDir) && dir.exists(baseDir)) {
        idat_files <- list.files(baseDir, pattern = "\\.idat$", full.names = TRUE)
        file.copy(idat_files, "idat_dir/")
        
        copied_files <- list.files("idat_dir", pattern = "\\.idat$")
        barcodes <- unique(sub("_(Grn|Red)\\.idat$", "", copied_files))
        sample_ids <- barcodes
    }
}

# Fallback to dummy IDAT files if minfiData is not available
if (length(list.files("idat_dir")) == 0) {
    for (bc in barcodes) {
        writeBin(as.raw(1:10), file.path("idat_dir", paste0(bc, "_Grn.idat")))
        writeBin(as.raw(1:10), file.path("idat_dir", paste0(bc, "_Red.idat")))
    }
}

# 2. Create geno_dir and populate with raw genotyping IDAT files
dir.create("geno_dir", showWarnings = FALSE)
for (bc in barcodes) {
    writeBin(as.raw(1:10), file.path("geno_dir", paste0(bc, "_Grn.idat")))
    writeBin(as.raw(1:10), file.path("geno_dir", paste0(bc, "_Red.idat")))
}

# 3. Create sample_annotation.tsv mapping sample IDs to barcodes and GenoSentrixPositions
anno <- data.frame(
  ID = sample_ids,
  age = c(14, 42, 45)[1:length(sample_ids)],
  sex = c("f", "f", "m")[1:length(sample_ids)],
  barcode = barcodes,
  GenoSentrixPosition = barcodes
)
write.table(anno, file = "sample_annotation.tsv", sep = "\t", row.names = FALSE, quote = FALSE)

# 4. Provide the pre-computed object as a fallback for the workflow
imp.data_path <- system.file("extdata", "reduced_methQTL", package = "MAGAR")
if (nzchar(imp.data_path) && dir.exists(imp.data_path)) {
    try({
        imp.data <- loadMethQTLInput(imp.data_path)
        saveRDS(imp.data, file = "imported_meth_qtl_data.rds")
    }, silent = TRUE)
}