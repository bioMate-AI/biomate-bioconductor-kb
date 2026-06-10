library(regioneR)

# Locate or generate Rad21.gz
rad21_file <- list.files(system.file("extdata", package="regioneR"), pattern="Rad21\\.gz$", full.names=TRUE, recursive=TRUE)
if (length(rad21_file) == 0) {
    rad21_file <- list.files(system.file("extdata", package="regioneR"), pattern="Rad21.*\\.gz$", full.names=TRUE, recursive=TRUE)
}

if (length(rad21_file) > 0) {
    file.copy(rad21_file[1], "Rad21.gz", overwrite = TRUE)
} else {
    # Fallback: create synthetic ChIP-seq peaks for Rad21
    rad21_gr <- createRandomRegions(nregions=100, length.mean=500, length.sd=100)
    df_rad21 <- data.frame(
        chrom = as.character(seqnames(rad21_gr)),
        start = start(rad21_gr) - 1,
        end = end(rad21_gr)
    )
    gz1 <- gzfile("Rad21.gz", "w")
    write.table(df_rad21, gz1, sep="\t", quote=FALSE, row.names=FALSE, col.names=FALSE)
    close(gz1)
}

# Locate or generate Ctcf.gz
ctcf_file <- list.files(system.file("extdata", package="regioneR"), pattern="Ctcf\\.gz$", full.names=TRUE, recursive=TRUE)
if (length(ctcf_file) == 0) {
    ctcf_file <- list.files(system.file("extdata", package="regioneR"), pattern="Ctcf.*\\.gz$", full.names=TRUE, recursive=TRUE)
}

if (length(ctcf_file) > 0) {
    file.copy(ctcf_file[1], "Ctcf.gz", overwrite = TRUE)
} else {
    # Fallback: create synthetic ChIP-seq peaks for CTCF
    ctcf_gr <- createRandomRegions(nregions=100, length.mean=500, length.sd=100)
    df_ctcf <- data.frame(
        chrom = as.character(seqnames(ctcf_gr)),
        start = start(ctcf_gr) - 1,
        end = end(ctcf_gr)
    )
    gz2 <- gzfile("Ctcf.gz", "w")
    write.table(df_ctcf, gz2, sep="\t", quote=FALSE, row.names=FALSE, col.names=FALSE)
    close(gz2)
}