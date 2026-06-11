library(knowYourCG)

# The vignette uses a query of CpGs methylated in mouse primordial germ cells.
# Since ExperimentHub/sesameDataCache requires online access, we use the exact 
# head() of the query shown in the vignette to construct the character vector.
query <- c(
    "cg36615889_TC11", 
    "cg36646136_BC21", 
    "cg36647910_BC11", 
    "cg36857173_TC21", 
    "cg36877289_BC21", 
    "cg36899653_BC21"
)

# Serialize the character vector to the working directory.
# Writing as both RDS and plain text to ensure compatibility with the workflow's read method.
saveRDS(query, "character vector.rds")
saveRDS(query, "character vector")
writeLines(query, "character vector.txt")