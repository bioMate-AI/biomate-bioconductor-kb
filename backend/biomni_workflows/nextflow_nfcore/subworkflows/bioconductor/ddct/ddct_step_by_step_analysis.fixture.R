library(ddCt)
library(Biobase)

exp_file <- system.file("extdata", "Experiment1.txt", package="ddCt")
if (file.exists(exp_file)) {
    file.copy(exp_file, "Experiment1.txt", overwrite = TRUE)
} else {
    df <- data.frame(
        Sample = rep(c("Sample1", "Sample2"), each=2),
        Detector = rep(c("Gene1", "Gene2"), 2),
        Task = rep("Unknown", 4),
        Ct = c(20, 21, 22, 23)
    )
    write.table(df, "Experiment1.txt", sep="\t", row.names=FALSE, quote=FALSE)
}

sample_file <- system.file("extdata", "sampleData.txt", package="ddCt")
if (file.exists(sample_file)) {
    file.copy(sample_file, "sampleData.txt", overwrite = TRUE)
} else {
    df_sample <- data.frame(
        Sample = c("Sample1", "Sample2", "Sample3"),
        Group = c("Control", "Treatment", "Treatment")
    )
    write.table(df_sample, "sampleData.txt", sep="\t", row.names=FALSE, quote=FALSE)
}