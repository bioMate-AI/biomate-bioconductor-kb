library(ORFhunteR)
library(Biostrings)
library(randomForest)

# 1. transcripts.fasta
# Use the example FASTA file shipped with the package if available, otherwise create a synthetic one
trans <- system.file("extdata", "Set.trans_sequences.fasta", package = "ORFhunteR")
if (file.exists(trans) && nzchar(trans)) {
  file.copy(trans, "transcripts.fasta", overwrite = TRUE)
} else {
  writeLines(c(">ENST00000235453", 
               "ATGGCGGCAGCTCCACGGGAGGAATGATTATCCATTTTCTCAATAA"), 
             "transcripts.fasta")
}

# 2. transcripts.gtf
# Create a minimal valid GTF file
gtf_content <- 'chr1\tHAVANA\ttranscript\t11869\t14409\t.\t+\t.\tgene_id "ENSG00000223972.5"; transcript_id "ENST00000456328.2"; gene_type "transcribed_unprocessed_pseudogene"; gene_name "DDX11L1"; transcript_type "lncRNA"; transcript_name "DDX11L1-202"; level 2; transcript_support_level "1"; hgnc_id "HGNC:37102"; tag "basic"; havana_gene "OTTHUMG00000000961.2"; havana_transcript "OTTHUMT00000362751.1";
chr1\tHAVANA\texon\t11869\t12227\t.\t+\t.\tgene_id "ENSG00000223972.5"; transcript_id "ENST00000456328.2"; gene_type "transcribed_unprocessed_pseudogene"; gene_name "DDX11L1"; transcript_type "lncRNA"; transcript_name "DDX11L1-202"; exon_number 1; exon_id "ENSE00002234944.1"; level 2; transcript_support_level "1"; hgnc_id "HGNC:37102"; tag "basic"; havana_gene "OTTHUMG00000000961.2"; havana_transcript "OTTHUMT00000362751.1";
'
writeLines(gtf_content, "transcripts.gtf")

# 3. classRFmodel.rds
# Generate synthetic ORF sequences to train a small Random Forest model
set.seed(123)
generate_seq <- function(n) {
  paste0("ATG", paste(sample(c("A","C","G","T"), n, replace=TRUE), collapse=""), "TAA")
}
ORFLncRNAs <- lapply(1:20, function(x) generate_seq(300))
ORFmRNAs <- lapply(1:20, function(x) generate_seq(300))

# Attempt to use the package's built-in model training function
tryCatch({
  clt <- classifyORFsCandidates(ORFLncRNAs = ORFLncRNAs, 
                                ORFmRNAs = ORFmRNAs, 
                                pLearn = 0.8, 
                                nTrees = 10, 
                                modelRF = "classRFmodel.rds", 
                                workDir = getwd(),
                                showAccuracy = FALSE)
}, error = function(e) {
  # Fallback: manually vectorize and train if the wrapper fails (e.g., due to small sample size)
  feats <- vectorizeORFs(x = DNAStringSet(x = unlist(c(ORFLncRNAs, ORFmRNAs))))
  feats$Class <- as.factor(rep(c("1", "3"), each = 20))
  rf_model <- randomForest(Class ~ ., data = feats, ntree = 10)
  saveRDS(rf_model, "classRFmodel.rds")
})

# Ensure the model file was created
if (!file.exists("classRFmodel.rds")) {
  feats <- vectorizeORFs(x = DNAStringSet(x = unlist(c(ORFLncRNAs, ORFmRNAs))))
  feats$Class <- as.factor(rep(c("1", "3"), each = 20))
  rf_model <- randomForest(Class ~ ., data = feats, ntree = 10)
  saveRDS(rf_model, "classRFmodel.rds")
}