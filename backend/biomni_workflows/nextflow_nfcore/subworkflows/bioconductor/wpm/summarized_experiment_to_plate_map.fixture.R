library(wpm)
library(SummarizedExperiment)

# Create a dummy SummarizedExperiment object based on the vignette's sample data structure
colData <- DataFrame(
  Sample = paste0("s", 1:4),
  Type = c("A", "A", "B", "C"),
  Treatment = c("trt1", "trt1", "Ctrl", "Ctrl"),
  row.names = paste0("s", 1:4)
)

counts <- matrix(runif(200 * 4, 1, 1e4), nrow = 200, ncol = 4)
se_obj <- SummarizedExperiment(assays = list(counts = counts), colData = colData)

# Serialize the object to the declared input file 'se'
saveRDS(se_obj, file = "se")