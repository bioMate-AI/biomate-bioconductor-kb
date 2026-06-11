library(snpStats)

# Load the example data provided by the snpStats package
data(ld.example)

# Serialize the objects to the exact filenames expected by the workflow
saveRDS(ceph.1mb, "ceph.1mb")
saveRDS(support.ld, "support.ld")