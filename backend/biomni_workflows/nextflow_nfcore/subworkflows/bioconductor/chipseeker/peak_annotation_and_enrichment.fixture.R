library(ChIPseeker)
library(TxDb.Hsapiens.UCSC.hg19.knownGene)

# Prepare and save the TxDb object
txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene
saveRDS(txdb, "txdb.rds")
saveRDS(txdb, "txdb") # Fallback for strict name matching

# Prepare and save the BED file
sample_files <- getSampleFiles()
bed_data <- read.table(sample_files[[4]], header = FALSE, sep = "\t", stringsAsFactors = FALSE)

write.table(bed_data, "files_4.bed", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)
write.table(bed_data, "files[[4]]", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE) # Fallback for strict name matching