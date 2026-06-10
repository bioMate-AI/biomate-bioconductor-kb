library(eisaR)

# Construct synthetic exonic count matrix
exonic_counts <- matrix(
  c(100, 120, 110, 130,
    50,  60,  55,  65,
    200, 210, 190, 220),
  nrow = 3,
  dimnames = list(
    c("ENSG00000223972.5", "ENSG00000243485.5", "ENSG00000284332.1"),
    c("Cond1_Rep1", "Cond1_Rep2", "Cond2_Rep1", "Cond2_Rep2")
  )
)

# Construct synthetic intronic count matrix
intronic_counts <- matrix(
  c(10, 12, 11, 13,
    5,  6,  5,  6,
    20, 21, 19, 22),
  nrow = 3,
  dimnames = list(
    c("ENSG00000223972.5", "ENSG00000243485.5", "ENSG00000284332.1"),
    c("Cond1_Rep1", "Cond1_Rep2", "Cond2_Rep1", "Cond2_Rep2")
  )
)

# Save to the required input files
saveRDS(exonic_counts, "rawcounts_exonic.rds")
saveRDS(intronic_counts, "rawcounts_intronic.rds")