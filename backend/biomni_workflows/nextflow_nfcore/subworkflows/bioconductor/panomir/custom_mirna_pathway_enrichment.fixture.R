library(PanomiR)

# Load the built-in datasets from PanomiR
data("targetScan_03", package = "PanomiR")
data("msigdb_c2", package = "PanomiR")

# Save the miRNA targets to RData
# We save both the original object name and a generic name to ensure compatibility
mirna_targets <- targetScan_03
save(targetScan_03, mirna_targets, file = "mirna_targets.RData")

# Save the pathway sets to RData
pathway_sets <- msigdb_c2
save(msigdb_c2, pathway_sets, file = "pathway_sets.RData")

# Extract a subset of genes to represent expressed genes
expressed_genes <- na.omit(unique(unlist(msigdb_c2)))[1:200]
writeLines(as.character(expressed_genes), "expressed_genes.txt")

# Extract a subset of miRNAs to represent expressed/selected miRNAs
expressed_mirnas <- names(targetScan_03)[1:50]
writeLines(as.character(expressed_mirnas), "expressed_mirnas.txt")

# Also write to selected_mirnas.txt as referenced in the structured input spec
writeLines(as.character(expressed_mirnas), "selected_mirnas.txt")