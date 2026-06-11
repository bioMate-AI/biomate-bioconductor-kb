library(knowYourCG)

# The vignette uses getDBs("MM285.designGroup")[["PGCMeth"]] to retrieve a query of CpGs.
# To ensure the script runs fully offline without ExperimentHub fetches, 
# we use the exact CG IDs shown in the vignette's head(query) output.
query <- c(
    "cg36615889_TC11", 
    "cg36646136_BC21", 
    "cg36647910_BC11", 
    "cg36857173_TC21", 
    "cg36877289_BC21", 
    "cg36899653_BC21"
)

# The workflow expects a named numeric vector of methylation levels (beta_values)
beta_values <- c(0.85, 0.92, 0.78, 0.88, 0.95, 0.81)
names(beta_values) <- query

# Save to the files expected by the workflow's read logic
# 1. As an RDS file without extension (checked first by the workflow)
saveRDS(beta_values, "beta_values")

# 2. As an RDS file with .rds extension
saveRDS(beta_values, "beta_values.rds")

# 3. As a CSV file with row names
df <- data.frame(beta_values = beta_values)
write.csv(df, "beta_values.csv", row.names = TRUE)