library(CellBarcode)
library(stringr)

example_data <- system.file("extdata", "mef_test_data", package = "CellBarcode")
fq_files <- dir(example_data, "fastq.gz", full=TRUE)

# prepare metadata for the samples
metadata <- stringr::str_split_fixed(basename(fq_files), "_", 10)[, c(4, 6)]
metadata <- as.data.frame(metadata)
sample_name <- apply(metadata, 1, paste, collapse = "_")
colnames(metadata) <- c("cell_number", "replication")
# metadata should has the row names consistent to the sample names
rownames(metadata) <- sample_name

write.csv(metadata, "metadata.csv", row.names = TRUE)
saveRDS(fq_files, "fq_files.rds")