# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("RcisTarget")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(RcisTarget)

# 1. Create gene_list.txt
# Using a representative list of gene symbols
gene_list <- c("BRCA1", "BRCA2", "TP53", "PTEN", "EGFR", "MYC", "FOS", "JUN", "SP1", "E2F1")
writeLines(gene_list, "gene_list.txt")

# 2. Create motif_rankings.db
# rcistarget uses Feather files for its ranking databases.
# The database is a table where rows are motifs and columns are genes.
# The first column must be 'features' containing the motif IDs.
motifs <- paste0("motif_", 1:100)
all_genes <- unique(c(gene_list, paste0("gene_", 1:200)))

rankings_df <- data.frame(features = motifs, stringsAsFactors = FALSE)

set.seed(123)
for (g in all_genes) {
    # Ranks are 1-based, up to the number of motifs
    rankings_df[[g]] <- sample(seq_along(motifs))
}

# Write the database using arrow or feather (dependencies of rcistarget)
if (requireNamespace("arrow", quietly = TRUE)) {
    arrow::write_feather(rankings_df, "motif_rankings.db")
} else if (requireNamespace("feather", quietly = TRUE)) {
    feather::write_feather(rankings_df, "motif_rankings.db")
} else {
    stop("Neither 'arrow' nor 'feather' package is available to write the database.")
}