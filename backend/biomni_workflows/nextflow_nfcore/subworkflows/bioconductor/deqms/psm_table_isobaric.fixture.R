# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DEqMS", "matrixStats")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DEqMS)
library(matrixStats) # Used in other vignette examples for rowMins

# Reproduce the data simulation from section 2.3.3 of the vignette
# "DEqMS analysis using a PSM table (isobaric labelled data)".
# The vignette states: "Since the PSM table is not provided in this example,
# we will use a simulated PSM count table." and proceeds to simulate
# protein expression matrix and PSM count table.

set.seed(123)

# Simulate protein expression matrix (log2 transformed)
protein.matrix.psm = matrix(rnorm(100*6, mean = 15, sd = 2), ncol = 6)
rownames(protein.matrix.psm) = paste0("Protein_", 1:100)
colnames(protein.matrix.psm) = paste0("Sample_", 1:6)

# Simulate PSM count table
psm.count.table.sim = data.frame(count = sample(1:50, 100, replace = TRUE),
                                 row.names = rownames(protein.matrix.psm))

# Combine the simulated protein expression matrix and PSM count table
# into a single data frame to represent the 'dat.psm' input file.
# This file would conceptually be read by the workflow to derive
# protein.matrix.psm and psm.count.table.sim.
dat.psm_df <- as.data.frame(protein.matrix.psm)
dat.psm_df$Protein_ID <- rownames(dat.psm_df)
dat.psm_df$PSM_Count <- psm.count.table.sim$count[match(rownames(dat.psm_df), rownames(psm.count.table.sim))]

# Reorder columns to have Protein_ID first, then sample columns, then PSM_Count
dat.psm_df <- dat.psm_df[, c("Protein_ID", colnames(protein.matrix.psm), "PSM_Count")]

# Serialize the combined data frame to the specified input file 'dat.psm'.
# Using tab-separated format, consistent with other read.table examples in the vignette.
write.table(dat.psm_df, "dat.psm", sep = "\t", row.names = FALSE, quote = FALSE)