library(kmcut)

extdata_dir <- system.file("extdata", package="kmcut")

# 1. survival_data.txt
sdat_src <- list.files(extdata_dir, pattern="survival_data\\.txt$", full.names=TRUE)
if (length(sdat_src) > 0) {
    file.copy(sdat_src[1], "survival_data.txt", overwrite=TRUE)
} else {
    sdat <- data.frame(
        sample_id = c("SEQC_NB001", "SEQC_NB002", "SEQC_NB003", "SEQC_NB004", "SEQC_NB005"),
        stime = c(1362, 2836, 1191, 220, 2217),
        scens = c(1, 1, 1, 1, 0)
    )
    write.table(sdat, "survival_data.txt", sep="\t", row.names=FALSE, quote=FALSE)
}

# 2. expression_data_1.txt
fdat1_src <- list.files(extdata_dir, pattern="expression_data_1\\.txt$", full.names=TRUE)
if (length(fdat1_src) > 0) {
    file.copy(fdat1_src[1], "expression_data_1.txt", overwrite=TRUE)
} else {
    fdat_src <- list.files(extdata_dir, pattern="example_genes\\.txt$", full.names=TRUE)
    if (length(fdat_src) > 0) {
        file.copy(fdat_src[1], "expression_data_1.txt", overwrite=TRUE)
    } else {
        fdat <- data.frame(
            tracking_id = c("MYCN", "MYH2"),
            SEQC_NB001 = c(4.16347458, 0.006539622),
            SEQC_NB002 = c(3.464994927, 0.009077256),
            SEQC_NB003 = c(8.494631614, 0),
            SEQC_NB004 = c(8.438018327, 4.111214977),
            SEQC_NB005 = c(5.509974474, 0.008735951)
        )
        write.table(fdat, "expression_data_1.txt", sep="\t", row.names=FALSE, quote=FALSE)
    }
}

# 3. expression_data_2.txt
fdat2_src <- list.files(extdata_dir, pattern="expression_data_2\\.txt$", full.names=TRUE)
if (length(fdat2_src) > 0) {
    file.copy(fdat2_src[1], "expression_data_2.txt", overwrite=TRUE)
} else {
    fdat_src <- list.files(extdata_dir, pattern="example_genes\\.txt$", full.names=TRUE)
    if (length(fdat_src) > 0) {
        file.copy(fdat_src[1], "expression_data_2.txt", overwrite=TRUE)
    } else {
        fdat <- data.frame(
            tracking_id = c("MYCN", "MYH2"),
            SEQC_NB001 = c(4.16347458, 0.006539622),
            SEQC_NB002 = c(3.464994927, 0.009077256),
            SEQC_NB003 = c(8.494631614, 0),
            SEQC_NB004 = c(8.438018327, 4.111214977),
            SEQC_NB005 = c(5.509974474, 0.008735951)
        )
        write.table(fdat, "expression_data_2.txt", sep="\t", row.names=FALSE, quote=FALSE)
    }
}