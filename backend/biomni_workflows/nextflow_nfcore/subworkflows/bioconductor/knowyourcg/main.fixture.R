library(knowYourCG)

# The vignette uses getDBs("MM285.designGroup")[["PGCMeth"]] which fetches from ExperimentHub.
# To ensure the script runs fully offline, we construct the exact character vector of cg-numbers 
# as shown in the vignette's head(query) output.
query <- c(
    "cg36615889_TC11", 
    "cg36646136_BC21", 
    "cg36647910_BC11", 
    "cg36857173_TC21", 
    "cg36877289_BC21", 
    "cg36899653_BC21"
)

# The workflow attempts to read the query file (via readRDS or readLines)
saveRDS(query, "query")