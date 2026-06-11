library(NormalyzerDE)

designFp <- system.file("extdata", "tiny_design.tsv", package="NormalyzerDE")
dataFp <- system.file("extdata", "tiny_data.tsv", package="NormalyzerDE")

if (file.exists(designFp)) {
    file.copy(designFp, "tiny_design.tsv", overwrite = TRUE)
} else {
    designDf <- data.frame(
        sample = c("s_125amol_1", "s_125amol_2", "s_125amol_3", "s_12500amol_1", "s_12500amol_2", "s_12500amol_3"),
        group = c("4", "4", "4", "2", "2", "2"),
        batch = c(2, 2, 2, 1, 1, 1)
    )
    write.table(designDf, "tiny_design.tsv", sep="\t", row.names=FALSE, quote=FALSE)
}

if (file.exists(dataFp)) {
    file.copy(dataFp, "tiny_data.tsv", overwrite = TRUE)
} else {
    dataDf <- data.frame(
        Cluster.ID = 1:100,
        Peptide.Sequence = rep("AAAAEINVKD", 100),
        External.IDs = rep("P38156", 100),
        Charge = rep(2, 100),
        Average.RT = seq(20, 40, length.out=100),
        Average.m.z = rep(501.268, 100),
        s_12500amol_1 = runif(100, 1e8, 1.2e8),
        s_12500amol_2 = runif(100, 1e8, 1.2e8),
        s_12500amol_3 = runif(100, 1e8, 1.2e8),
        s_125amol_1 = runif(100, 8e7, 1e8),
        s_125amol_2 = runif(100, 8e7, 1e8),
        s_125amol_3 = runif(100, 8e7, 1e8)
    )
    write.table(dataDf, "tiny_data.tsv", sep="\t", row.names=FALSE, quote=FALSE)
}