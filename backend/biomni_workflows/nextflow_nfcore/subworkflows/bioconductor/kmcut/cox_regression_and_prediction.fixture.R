library(kmcut)

fdat <- system.file("extdata", "example_genes.txt", package="kmcut")
sdat <- system.file("extdata", "survival_data.txt", package="kmcut")

if (file.exists(fdat) && nzchar(fdat)) {
    file.copy(fdat, "expression_data_1.txt", overwrite = TRUE)
    file.copy(fdat, "expression_data_2.txt", overwrite = TRUE)
} else {
    expr_data <- data.frame(
        tracking_id = c("MYCN", "MYH2"),
        SEQC_NB001 = c(4.16347458, 0.006539622),
        SEQC_NB002 = c(3.464994927, 0.009077256),
        SEQC_NB003 = c(8.494631614, 0),
        SEQC_NB004 = c(8.438018327, 4.111214977),
        SEQC_NB005 = c(5.509974474, 0.008735951)
    )
    write.table(expr_data, "expression_data_1.txt", sep = "\t", row.names = FALSE, quote = FALSE)
    write.table(expr_data, "expression_data_2.txt", sep = "\t", row.names = FALSE, quote = FALSE)
}

if (file.exists(sdat) && nzchar(sdat)) {
    file.copy(sdat, "survival_data.txt", overwrite = TRUE)
} else {
    surv_data <- data.frame(
        sample_id = c("SEQC_NB001", "SEQC_NB002", "SEQC_NB003", "SEQC_NB004", "SEQC_NB005"),
        stime = c(1362, 2836, 1191, 220, 2217),
        scens = c(1, 1, 1, 1, 0)
    )
    write.table(surv_data, "survival_data.txt", sep = "\t", row.names = FALSE, quote = FALSE)
}