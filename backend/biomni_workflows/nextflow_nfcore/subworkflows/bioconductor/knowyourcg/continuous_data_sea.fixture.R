library(knowYourCG)

# Create a synthetic named numeric vector representing CpG probes with continuous values (e.g., beta values)
set.seed(123)
cpg_ids <- paste0("cg", sprintf("%08d", sample(1:99999999, 1000)))
input_data <- setNames(runif(1000, min = 0, max = 1), cpg_ids)

# Save the object to the working directory
saveRDS(input_data, "named_numeric_vector.rds")