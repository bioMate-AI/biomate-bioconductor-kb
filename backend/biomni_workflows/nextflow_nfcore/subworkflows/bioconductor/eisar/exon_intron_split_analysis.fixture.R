library(eisaR)

# Generate synthetic exonic and intronic count matrices
# matching the expected format of raw count tables
set.seed(123)
genes <- paste0("Gene", 1:100)
samples <- c("Cond1_Rep1", "Cond1_Rep2", "Cond2_Rep1", "Cond2_Rep2")

cntEx <- matrix(rpois(400, lambda = 100), nrow = 100, ncol = 4, 
                dimnames = list(genes, samples))
cntIn <- matrix(rpois(400, lambda = 20), nrow = 100, ncol = 4, 
                dimnames = list(genes, samples))

# Save to the expected RDS files
saveRDS(cntEx, "Fig3abc_GSE33252_rawcounts_exonic.rds")
saveRDS(cntIn, "Fig3abc_GSE33252_rawcounts_intronic.rds")