library(knowYourCG)

# The vignette uses a query of CpGs methylated in mouse primordial germ cells.
# To ensure the script runs fully offline without ExperimentHub/sesameDataCache fetches,
# we construct the character vector of CpG probe IDs exactly as shown in the vignette's head(query) output.
query <- c(
    "cg36615889_TC11", 
    "cg36646136_BC21", 
    "cg36647910_BC11", 
    "cg36857173_TC21", 
    "cg36877289_BC21", 
    "cg36899653_BC21"
)

# Serialize the character vector to an RDS file
saveRDS(query, "input.rds")