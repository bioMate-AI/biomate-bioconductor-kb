# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("chromPlot")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("chromPlot")

# Ensure stringsAsFactors is set as in the vignette for consistency
options(stringsAsFactors = FALSE)

# 1. Recreate and save mm10_gap
# From vignette chunk 17
data(mm10_gap)
saveRDS(mm10_gap, "mm10_gap")

# 2. Recreate and save mm10_cytoBandIdeo
# This dataset is used in multiple chromPlot calls (e.g., chunk 18, 29, 33)
# and is a standard dataset within the chromPlot package, similar to hg_cytoBandIdeo.
data(mm10_cytoBandIdeo)
saveRDS(mm10_cytoBandIdeo, "mm10_cytoBandIdeo")

# 3. Recreate and save qtl
# From vignette chunk 32
data_file12 <- system.file("extdata", "QTL.csv", package = "chromPlot")
qtl <- read.table(data_file12, sep = ",", header = TRUE, stringsAsFactors = FALSE)
write.table(qtl, "qtl", sep = ",", row.names = FALSE, quote = FALSE)

# 4. Recreate and save ref_mm10
# From vignette chunk 16
data_file4 <- system.file("extdata", "mm10_refGeneChr2-11-17-19.txt", package = "chromPlot")
ref_mm10 <- read.table(data_file4, sep = "\t", stringsAsFactors = FALSE, header = TRUE)
write.table(ref_mm10, "ref_mm10", sep = "\t", row.names = FALSE, quote = FALSE)

# 5. Recreate and save pheno_ancestry
# From vignette chunk 34
data_file11 <- system.file("extdata", "phenogram-ancestry-sample.txt", package = "chromPlot")
pheno_ancestry <- read.csv(data_file11, sep = "\t", header = TRUE)
# Apply modification from vignette chunk 36
pheno_ancestry$Start <- pheno_ancestry$Start - 5e6
pheno_ancestry$End <- pheno_ancestry$End + 5e6
write.table(pheno_ancestry, "pheno_ancestry", sep = "\t", row.names = FALSE, quote = FALSE)

# 6. Recreate and save ancestry
# From vignette chunk 38
data_file13 <- system.file("extdata", "ancestry_humanChr19-21.txt", package = "chromPlot")
ancestry <- read.table(data_file13, sep = "\t", stringsAsFactors = FALSE, header = TRUE)
write.table(ancestry, "ancestry", sep = "\t", row.names = FALSE, quote = FALSE)

# 7. Recreate and save region
# From vignette chunk 41
data_file14 <- system.file("extdata", "donor_regions.csv", package = "chromPlot")
region <- read.csv(data_file14, sep = ",")
region$Colors <- "darkred"
write.table(region, "region", sep = ",", row.names = FALSE, quote = FALSE)