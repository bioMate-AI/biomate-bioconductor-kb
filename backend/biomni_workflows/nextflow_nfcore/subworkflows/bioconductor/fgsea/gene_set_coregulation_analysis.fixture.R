# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("fgsea")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(fgsea)

# Load example pathways shipped with fgsea
data(examplePathways, package = "fgsea")

# Save pathways list
saveRDS(examplePathways, "pathways_list.rds")

# Generate a synthetic expression matrix based on the genes in examplePathways
set.seed(42)
all_genes <- unique(unlist(examplePathways))

# Subset to 1000 genes to keep it small but realistic
if(length(all_genes) > 1000) {
    all_genes <- all_genes[1:1000]
}

n_samples <- 12
expr_matrix <- matrix(rnorm(length(all_genes) * n_samples, mean = 15, sd = 2), 
                      nrow = length(all_genes), ncol = n_samples)
rownames(expr_matrix) <- all_genes
colnames(expr_matrix) <- paste0("Sample_", 1:n_samples)

# Introduce some correlation for a specific pathway to simulate co-regulation
target_pathway <- examplePathways[[1]]
target_genes <- intersect(target_pathway, all_genes)
if(length(target_genes) > 0) {
    # Add a pattern across samples
    pattern <- seq(-2, 2, length.out = n_samples)
    for(i in seq_along(target_genes)) {
        expr_matrix[target_genes[i], ] <- expr_matrix[target_genes[i], ] + pattern * 3
    }
}

# Write expression matrix to CSV
write.csv(expr_matrix, "expression_matrix.csv", row.names = TRUE)