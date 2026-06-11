library(vtpnet)

# 1. gwas_variants.GRanges
data(maurGWAS)
saveRDS(maurGWAS, "gwas_variants.GRanges")

# 2. tf_binding_sites.GRanges
data(pax4)
saveRDS(pax4, "tf_binding_sites.GRanges")

# 3. disease_map.RData
data(cancerMap)
save(cancerMap, file="disease_map.RData")