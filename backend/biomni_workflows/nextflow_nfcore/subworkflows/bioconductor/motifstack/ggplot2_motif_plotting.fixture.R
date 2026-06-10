library(motifStack)

pcm_file <- system.file("extdata", "bin_SOLEXA.pcm", package="motifStack")
pcm <- read.table(pcm_file)
pcm <- pcm[, 3:ncol(pcm)]
rownames(pcm) <- c("A", "C", "G", "T")

pfm_mat <- pcm2pfm(pcm)
motif <- new("pfm", mat=pfm_mat, name="bin_SOLEXA")

saveRDS(motif, "pfm_object.rds")