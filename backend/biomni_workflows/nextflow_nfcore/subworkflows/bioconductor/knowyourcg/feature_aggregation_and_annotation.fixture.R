library(knowYourCG)

# The vignette uses MM285 design group PGCMeth as an example query:
# query <- getDBs("MM285.designGroup")[["PGCMeth"]]
# head(query)
# [1] "cg36615889_TC11" "cg36646136_BC21" "cg36647910_BC11" "cg36857173_TC21"
# [5] "cg36877289_BC21" "cg36899653_BC21"

# Since we must run offline and cannot use sesameDataCache/ExperimentHub,
# we construct a synthetic query and betas matrix using the exact probe IDs 
# from the vignette's example.

query <- c(
    "cg36615889_TC11", 
    "cg36646136_BC21", 
    "cg36647910_BC11", 
    "cg36857173_TC21", 
    "cg36877289_BC21", 
    "cg36899653_BC21"
)

# Construct a synthetic betas matrix (probes x samples)
betas <- matrix(
    c(0.85, 0.90, 0.10, 0.15, 0.88, 0.92,
      0.80, 0.95, 0.12, 0.20, 0.85, 0.89),
    nrow = length(query),
    ncol = 2,
    dimnames = list(query, c("Sample1", "Sample2"))
)

# Write the expected input files
saveRDS(betas, "betas.rds")
saveRDS(query, "query.rds")