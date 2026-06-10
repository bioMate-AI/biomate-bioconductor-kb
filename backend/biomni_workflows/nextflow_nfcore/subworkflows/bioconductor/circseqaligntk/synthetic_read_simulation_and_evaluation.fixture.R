library(CircSeqAlignTk)
genome_seq <- system.file("extdata", "FR851463.fa", package = "CircSeqAlignTk")
file.copy(genome_seq, "FR851463.fa", overwrite = TRUE)