# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("cTRAP")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(cTRAP)

# Load ENCODE RNA-seq data and perform differential gene expression analysis
gene <- "EIF4G1"
cellLine <- "HepG2"
ENCODEmetadata <- downloadENCODEknockdownMetadata(cellLine, gene)
ENCODEsamples <- loadENCODEsamples(ENCODEmetadata)[[1]]
counts <- prepareENCODEgeneExpression(ENCODEsamples)

# Remove low coverage (at least 10 counts shared across two samples)
minReads <- 10
minSamples <- 2
filter <- rowSums(counts[, -c(1, 2)] >= minReads) >= minSamples
counts <- counts[filter, ]

# Convert ENSEMBL identifier to gene symbol
counts$gene_id <- convertGeneIdentifiers(counts$gene_id)

# Perform differential gene expression analysis
diffExpr <- performDifferentialExpression(counts)

# Get t-statistics of differential expression with respective gene names
# (expected input for downstream analyses)
diffExprStat <- diffExpr$t
names(diffExprStat) <- diffExpr$Gene_symbol

# Serialize the diffExprStat object to diffExprStat.rds
saveRDS(diffExprStat, "diffExprStat.rds")

# Serialize the diffExprStat object to diffExprStat.csv
# The workflow reads this with read.csv("diffExprStat.csv", row.names = 1)
# This means the first column of the CSV should be the row names (gene symbols)
# and the second column should be the t-statistic.
df_for_csv <- data.frame(t = diffExprStat)
write.csv(df_for_csv, "diffExprStat.rds", row.names = names(diffExprStat))