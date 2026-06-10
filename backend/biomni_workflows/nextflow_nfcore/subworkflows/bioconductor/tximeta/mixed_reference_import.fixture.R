library(tximeta)

# Discover and copy the Oarfish quantification file shipped with the package
quant_file <- list.files(system.file("extdata", package="tximeta"), 
                         pattern="experiment_rep1.quant.gz", 
                         recursive=TRUE, full.names=TRUE)[1]

if (!is.na(quant_file) && file.exists(quant_file)) {
    file.copy(quant_file, "experiment_rep1.quant.gz", overwrite = TRUE)
} else {
    # Fallback: create a minimal synthetic Oarfish quantification file
    df <- data.frame(tname = c("tx1", "tx2"), 
                     len = c(100, 200), 
                     num_reads = c(10, 20))
    gz1 <- gzfile("experiment_rep1.quant.gz", "w")
    write.table(df, gz1, sep="\t", quote=FALSE, row.names=FALSE)
    close(gz1)
}

# Discover and copy the sample metadata sheet shipped with the package
sample_table_file <- list.files(system.file("extdata", package="tximeta"), 
                                pattern="sample_table.csv", 
                                recursive=TRUE, full.names=TRUE)[1]

if (!is.na(sample_table_file) && file.exists(sample_table_file)) {
    st <- read.csv(sample_table_file, stringsAsFactors = FALSE)
    # Ensure the files column points to the local file we just created/copied
    st$files <- "experiment_rep1.quant.gz"
    write.csv(st, "sample_table.csv", row.names=FALSE)
} else {
    # Fallback: create a minimal synthetic sample table
    coldata <- data.frame(
        names = "experiment_rep1",
        files = "experiment_rep1.quant.gz",
        condition = "A",
        stringsAsFactors = FALSE
    )
    write.csv(coldata, "sample_table.csv", row.names=FALSE)
}