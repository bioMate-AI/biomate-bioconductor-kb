library("GenomicDistributions")
library("rtracklayer")

queryFile_pkg <- system.file("extdata", "vistaEnhancers.bed.gz", package="GenomicDistributions")
query <- rtracklayer::import(queryFile_pkg)

rtracklayer::export(query, "queryFile.bed", format = "BED")