library(APAlyzer)
library(TBX20BamSubset)
library(GenomicFeatures)
library(GenomicRanges)

extdata_dir <- system.file("extdata", package="APAlyzer")

# 1. flsall (List of RNA-seq BAM files)
flsall_path <- list.files(extdata_dir, pattern="flsall", full.names=TRUE, recursive=TRUE)
if (length(flsall_path) > 0) {
    file.copy(flsall_path[1], "flsall")
} else {
    flsall <- getBamFileList()
    saveRDS(flsall, "flsall")
}

# 2. mm9.chr19.refGene.R.DB (TxDb database file)
db_path <- list.files(extdata_dir, pattern="mm9.chr19.refGene.R.DB", full.names=TRUE, recursive=TRUE)
if (length(db_path) > 0) {
    file.copy(db_path[1], "mm9.chr19.refGene.R.DB")
} else {
    gr <- GRanges(
        seqnames = "chr19", 
        ranges = IRanges(start = 1, end = 1000), 
        strand = "+", 
        type = "exon", 
        transcript_id = "t1", 
        gene_id = "1"
    )
    txdb <- makeTxDbFromGRanges(gr)
    saveDb(txdb, "mm9.chr19.refGene.R.DB")
}