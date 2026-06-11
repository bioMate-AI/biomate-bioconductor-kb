library(wpm)
library(SummarizedExperiment)

# Create a synthetic SummarizedExperiment object with sample metadata
colData <- DataFrame(
    Sample = paste0("s", 1:8),
    Group = rep(c("A", "B"), each = 4),
    row.names = paste0("s", 1:8)
)

counts <- matrix(rpois(80, lambda = 10), ncol = 8)
colnames(counts) <- rownames(colData)

se <- SummarizedExperiment(
    assays = list(counts = counts),
    colData = colData
)

# Save the object to the expected input file
saveRDS(se, "se.rds")