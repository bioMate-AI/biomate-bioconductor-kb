library(QuasR)

extdata_dir <- system.file("extdata", package = "QuasR")

# 1. Prepare hg19sub.fa
fasta_file <- list.files(extdata_dir, pattern = "^hg19sub\\.fa$", recursive = TRUE, full.names = TRUE)[1]
if (!is.na(fasta_file) && file.exists(fasta_file)) {
    file.copy(fasta_file, "hg19sub.fa", overwrite = TRUE)
} else {
    # Fallback if not found
    writeLines(c(">chr1", "ACGTACGTACGT"), "hg19sub.fa")
}

# 2. Prepare samples_bis_single.txt and its referenced sequence files
samples_file <- list.files(extdata_dir, pattern = "^samples_bis_single\\.txt$", recursive = TRUE, full.names = TRUE)[1]
if (!is.na(samples_file) && file.exists(samples_file)) {
    df <- read.delim(samples_file, header = TRUE, stringsAsFactors = FALSE)
    
    # Copy any referenced sequence files to the working directory and update paths
    if ("FileName" %in% colnames(df)) {
        all_ext_files <- list.files(extdata_dir, recursive = TRUE, full.names = TRUE)
        for (i in seq_len(nrow(df))) {
            orig_path <- df$FileName[i]
            bname <- basename(orig_path)
            
            actual_file <- all_ext_files[basename(all_ext_files) == bname][1]
            if (!is.na(actual_file) && file.exists(actual_file)) {
                file.copy(actual_file, bname, overwrite = TRUE)
                df$FileName[i] <- bname
            }
        }
    }
    
    write.table(df, "samples_bis_single.txt", sep = "\t", row.names = FALSE, quote = FALSE)
} else {
    # Fallback if not found
    writeLines(c("FileName\tSampleName"), "samples_bis_single.txt")
}