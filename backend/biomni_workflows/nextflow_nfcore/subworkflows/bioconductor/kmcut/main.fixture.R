library(kmcut)

fdat_candidates <- list.files(system.file("extdata", package="kmcut"), pattern="example_genes.txt", full.names=TRUE, recursive=TRUE)
if (length(fdat_candidates) > 0) {
    file.copy(fdat_candidates[1], "example_genes.txt", overwrite=TRUE)
} else {
    genes <- data.frame(
        tracking_id = c("MYCN", "MYH2"),
        SEQC_NB001 = c(4.16347458, 0.006539622),
        SEQC_NB002 = c(3.464994927, 0.009077256),
        SEQC_NB003 = c(8.494631614, 0),
        SEQC_NB004 = c(8.438018327, 4.111214977),
        SEQC_NB005 = c(5.509974474, 0.008735951)
    )
    write.table(genes, "example_genes.txt", sep="\t", row.names=FALSE, quote=FALSE)
}

sdat_candidates <- list.files(system.file("extdata", package="kmcut"), pattern="survival_data.txt", full.names=TRUE, recursive=TRUE)
if (length(sdat_candidates) > 0) {
    file.copy(sdat_candidates[1], "survival_data.txt", overwrite=TRUE)
} else {
    surv <- data.frame(
        sample_id = c("SEQC_NB001", "SEQC_NB002", "SEQC_NB003", "SEQC_NB004", "SEQC_NB005"),
        stime = c(1362, 2836, 1191, 220, 2217),
        scens = c(1, 1, 1, 1, 0)
    )
    write.table(surv, "survival_data.txt", sep="\t", row.names=FALSE, quote=FALSE)
}