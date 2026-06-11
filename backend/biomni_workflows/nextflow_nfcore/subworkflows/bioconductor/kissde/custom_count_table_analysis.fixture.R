library(kissDE)

fpath1 <- system.file("extdata", "table_counts_alt_splicing.txt", package = "kissDE")

if (fpath1 != "" && file.exists(fpath1)) {
    file.copy(fpath1, "table_counts_alt_splicing.txt", overwrite = TRUE)
} else {
    # Construct the synthetic file based on the vignette's example
    tableCounts <- data.frame(
        eventsName = c("event1", "event1", "event2", "event2", "event3", "event3"),
        eventsLength = c(261, 81, 207, 80, 268, 82),
        cond1rep1 = c(105, 2, 20, 58, 53, 3),
        cond1rep2 = c(41, 5, 17, 33, 26, 1),
        cond2rep1 = c(15, 100, 60, 7, 19, 31),
        cond2rep2 = c(26, 150, 58, 1, 29, 55),
        stringsAsFactors = FALSE
    )
    write.table(tableCounts, "table_counts_alt_splicing.txt", sep = "\t", quote = FALSE, row.names = FALSE)
}