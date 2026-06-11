library(ORFhunteR)
library(Biostrings)
library(randomForest)
library(rtracklayer)
library(GenomicRanges)

# 1. trans_sequences.fasta
# Copy the example fasta file shipped with the package
trans <- system.file("extdata", "Set.trans_sequences.fasta", package = "ORFhunteR")
file.copy(trans, "trans_sequences.fasta")

# 2. classRFmodel_1.rds
# Generate a dummy Random Forest model with the exact features expected by predictORF()
dummy_seqs <- DNAStringSet(c("ATGGGCCTCTAA", "ATGAAACCCTAA"))
feats <- vectorizeORFs(dummy_seqs)

# Replicate to have enough samples for randomForest to train
dummy_data <- as.data.frame(feats[rep(1:2, 10), ])

# Add slight noise to avoid constant variables warning/error in randomForest
set.seed(123)
for(i in seq_len(ncol(dummy_data))) {
    if(is.numeric(dummy_data[, i])) {
        dummy_data[, i] <- dummy_data[, i] + rnorm(nrow(dummy_data), mean = 0, sd = 0.001)
    }
}

# ORFhunteR typically uses "1" for pseudo-ORFs and "3" for true ORFs
dummy_data$Class <- factor(rep(c("1", "3"), 10))

rf_model <- randomForest(Class ~ ., data = dummy_data, ntree = 5)
saveRDS(rf_model, "classRFmodel_1.rds")

# 3. trans_sequences.gtf
# Create a dummy GTF file with a transcript ID that matches the fasta file
gr <- GRanges(seqnames = "chr1", 
              ranges = IRanges(start = 1, end = 1000), 
              strand = "+", 
              type = "exon", 
              transcript_id = "ENST00000235453", 
              gene_id = "ENSG000001")
export(gr, "trans_sequences.gtf", format = "gtf")

# Verify all files exist
stopifnot(
  file.exists("trans_sequences.fasta"),
  file.exists("classRFmodel_1.rds"),
  file.exists("trans_sequences.gtf")
)