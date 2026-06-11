library(MetaPhOR)

# Construct a synthetic DEG list matching the format expected by MetaPhOR
# Includes HUGO gene names, log fold change, and adjusted p-values
degs <- data.frame(
  X = c("TATDN1", "ZNF706", "DCAF13", "TRMT12", "IGF2BP1", "MAP6D1", 
        "CRLS1", "HMGCR", "CS", "MDH1", "IDH1", "ACO1"),
  logFC = c(0.0996779, 0.1055866, 0.0882855, 0.1093866, 0.9256589, 0.1619178, 
            1.2, -0.5, 0.8, 0.3, -0.2, 0.4),
  AveExpr = rep(6.0, 12),
  t = rep(5.0, 12),
  P.Value = rep(1e-5, 12),
  adj.P.Val = rep(1e-4, 12),
  B = rep(7.0, 12)
)

# Write the input file to the working directory
write.csv(degs, "BRCA_DEGS.csv", row.names = FALSE)