suppressPackageStartupMessages({
    library(APAlyzer)
    library(TBX20BamSubset)
    library(Rsamtools)
    library(GenomicFeatures)
    library(AnnotationDbi)
})

# 1. flsall: named vector of paths to BAM files
# Using the exact data package and function from the vignette
flsall <- getBamFileList()
saveRDS(flsall, "flsall.rds")

# 2. txdb: TxDb object loaded from annotation
# The vignette uses mouse (mm9) data, so we use the corresponding TxDb if available
if (requireNamespace("TxDb.Mmusculus.UCSC.mm9.knownGene", quietly = TRUE)) {
    txdb <- TxDb.Mmusculus.UCSC.mm9.knownGene::TxDb.Mmusculus.UCSC.mm9.knownGene
} else {
    # Fallback to a minimal synthetic TxDb if the specific package is missing
    gr <- GRanges(seqnames = "chr19", 
                  ranges = IRanges(start = c(1000, 2000), end = c(1500, 2500)), 
                  strand = "+", 
                  type = "exon", 
                  exon_id = c(1, 2),
                  gene_id = c("1", "1"),
                  transcript_id = c("t1", "t1"))
    txdb <- makeTxDbFromGRanges(gr)
}
# The workflow supports reading from txdb.sqlite via loadDb()
saveDb(txdb, "txdb.sqlite")

# 3. IDDB: org.Db object for gene identifier mapping
# Using the standard mouse org.Db package
if (requireNamespace("org.Mm.eg.db", quietly = TRUE)) {
    IDDB <- org.Mm.eg.db::org.Mm.eg.db
    saveRDS(IDDB, "IDDB.rds")
} else {
    # Fallback to ensure the file exists if the package is missing
    saveRDS(list(), "IDDB.rds")
}