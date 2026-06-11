library(geva)

set.seed(1)
genes <- paste0("probe_", 1:1000)

file_names <- c("cond_A_2h.txt", "cond_B_2h.txt", "cond_C_2h.txt",
                "cond_A_4h.txt", "cond_B_4h.txt", "cond_C_4h.txt")

for (fn in file_names) {
    df <- data.frame(
        logFC = rnorm(1000, mean = 0, sd = 1.5),
        adj.P.Val = runif(1000, min = 0, max = 1),
        row.names = genes
    )
    write.table(df, file = fn, sep = "\t", quote = FALSE, col.names = NA)
}