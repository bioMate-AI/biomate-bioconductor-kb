library(knowYourCG)

# The vignette uses getDBs("MM285.designGroup")[["PGCMeth"]] which fetches from ExperimentHub.
# To comply with the strict OFFLINE requirement, we use the exact output shown in the vignette's head(query)
query_probes <- c(
    "cg36615889_TC11", 
    "cg36646136_BC21", 
    "cg36647910_BC11", 
    "cg36857173_TC21", 
    "cg36877289_BC21", 
    "cg36899653_BC21"
)

writeLines(query_probes, "query_probes.txt")