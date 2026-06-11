library(ribosomeProfilingQC)
library(AnnotationDbi)
library(Rsamtools)
library(BSgenome.Drerio.UCSC.danRer10)

if (requireNamespace("txdbmaker", quietly = TRUE)) {
    library(txdbmaker)
} else {
    library(GenomicFeatures)
}

genome <- Drerio

# 1. Prepare CDS
gtf_file <- list.files(system.file("extdata", package="ribosomeProfilingQC"), 
                       pattern="Danio_rerio.GRCz10.91.chr1.gtf.gz", 
                       full.names=TRUE, recursive=TRUE)[1]

txdb <- makeTxDbFromGFF(gtf_file, 
                        organism = "Danio rerio", 
                        chrominfo = seqinfo(Drerio)["chr1"], 
                        taxonomyId = 7955)
CDS <- prepareCDS(txdb)
saveRDS(CDS, "CDS.rds")

# 2. Prepare pc (P-site coordinates)
bamfilename <- list.files(system.file("extdata", package="ribosomeProfilingQC"), 
                          pattern="RPF.WT.1.bam$", 
                          full.names=TRUE, recursive=TRUE)[1]

bamfile <- BamFile(bamfilename, yieldSize = 10000000)
pc <- getPsiteCoordinates(bamfile, bestpsite = 13)
saveRDS(pc, "pc.rds")

# 3. Prepare danrer10.annotations
danrer10_file <- list.files(system.file("extdata", package="ribosomeProfilingQC"), 
                            pattern="danrer10.annotations.rds", 
                            full.names=TRUE, recursive=TRUE)

if (length(danrer10_file) > 0) {
    file.copy(danrer10_file[1], "danrer10.annotations.rds", overwrite = TRUE)
} else {
    # Fallback if the file is not found in the current installation
    danrer10.annotations <- list(protein = names(CDS))
    saveRDS(danrer10.annotations, "danrer10.annotations.rds")
}