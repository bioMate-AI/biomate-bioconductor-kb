library(SpliceWiz)

# 1. Generate the NxtSE object using SpliceWiz's built-in example
se <- SpliceWiz_example_NxtSE()

# Add a mock condition to colData for differential expression
colData(se)$Condition <- rep(c("A", "B"), each = 3)

# 2. Generate differential expression results using edgeR
# SpliceWiz provides ASE_edgeR for this purpose
res_edgeR <- ASE_edgeR(
    se = se,
    test_factor = "Condition",
    test_nom = "A",
    test_denom = "B"
)

# 3. Serialize the objects to the working directory
saveRDS(se, "se")
saveRDS(res_edgeR, "res_edgeR")