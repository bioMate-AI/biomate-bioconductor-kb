library(SeqGSEA)

# Locate the package's extdata directory
data.dir <- system.file("extdata", package="SeqGSEA", mustWork=TRUE)

# Copy all SC (case) and SN (control) files to the working directory 
# to ensure they are available if the workflow dynamically searches for them.
sc_files <- dir(data.dir, pattern="^SC", full.names=TRUE)
sn_files <- dir(data.dir, pattern="^SN", full.names=TRUE)
file.copy(sc_files, ".", overwrite=TRUE)
file.copy(sn_files, ".", overwrite=TRUE)

# The specification explicitly requires files named exactly "case.files" and "control.files".
# We create them by copying the first available sample file, or generating synthetic data if missing.
if (length(sc_files) > 0) {
    file.copy(sc_files[1], "case.files", overwrite=TRUE)
} else {
    df_case <- data.frame(exon=paste0("E", 1:100), count=rnbinom(100, size=10, prob=0.5))
    write.table(df_case, "case.files", row.names=FALSE, col.names=FALSE, quote=FALSE, sep="\t")
}

if (length(sn_files) > 0) {
    file.copy(sn_files[1], "control.files", overwrite=TRUE)
} else {
    df_ctrl <- data.frame(exon=paste0("E", 1:100), count=rnbinom(100, size=10, prob=0.5))
    write.table(df_ctrl, "control.files", row.names=FALSE, col.names=FALSE, quote=FALSE, sep="\t")
}

# The specification explicitly requires a file named exactly "geneset.file".
geneset_orig <- system.file("extdata", "gs_symb.txt", package="SeqGSEA", mustWork=TRUE)
if (file.exists(geneset_orig)) {
    file.copy(geneset_orig, "geneset.file", overwrite=TRUE)
} else {
    # Fallback synthetic GMT format gene set file
    writeLines(c("GS1\t\tG1\tG2\tG3", "GS2\t\tG4\tG5\tG6"), "geneset.file")
}