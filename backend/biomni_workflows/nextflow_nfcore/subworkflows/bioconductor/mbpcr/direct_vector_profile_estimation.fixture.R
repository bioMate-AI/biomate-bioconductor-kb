library(mBPCR)
data(jekoChr11Array250Knsp)
# Workflow loads this input with readRDS(); save() writes an RData blob that readRDS
# cannot parse. Serialize the object itself so the read contract is satisfied.
saveRDS(jekoChr11Array250Knsp, "jekoChr11Array250Knsp")