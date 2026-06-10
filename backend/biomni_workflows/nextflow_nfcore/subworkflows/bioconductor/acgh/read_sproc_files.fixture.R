library(aCGH)

datadir <- system.file("examples", package = "aCGH")

# The workflow expects these specific files in the working directory
expected_files <- c("sprocCR40.txt", "sprocCR43.txt", "human.clones.info.Jul03.txt")

for (f in expected_files) {
    src <- file.path(datadir, f)
    
    if (file.exists(src)) {
        # Copy the exact file shipped with the package
        file.copy(src, f, overwrite = TRUE)
    } else {
        # Fallback: Construct synthetic files matching the expected format if missing
        if (f == "human.clones.info.Jul03.txt") {
            ex_info <- file.path(datadir, "clones.info.ex.txt")
            if (file.exists(ex_info)) {
                file.copy(ex_info, f, overwrite = TRUE)
            } else {
                df <- data.frame(Clone = paste0("C", 1:10), Chrom = 1, kb = 1:10)
                write.table(df, f, sep="\t", row.names=FALSE, quote=FALSE)
            }
        } else {
            # Construct a synthetic Sproc data file
            ex_log2 <- file.path(datadir, "log2.ratios.ex.txt")
            if (file.exists(ex_log2)) {
                log2_df <- read.table(ex_log2, header=TRUE, sep="\t", quote="", comment.char="")
                # Sproc files typically require Clone and Log2Ratio columns
                df <- data.frame(Clone = log2_df[,1], Log2Ratio = log2_df[,2])
                write.table(df, f, sep="\t", row.names=FALSE, quote=FALSE)
            } else {
                df <- data.frame(Clone = paste0("C", 1:10), Log2Ratio = rnorm(10))
                write.table(df, f, sep="\t", row.names=FALSE, quote=FALSE)
            }
        }
    }
}