# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Biobase", "gCrisprTools")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(Biobase)
library(gCrisprTools)

# 1. Load the primary results data.frame from the package
data(resultsDF)

# 2. Create a simplified result and a secondary result (res2) for comparison
res <- ct.simpleResult(resultsDF, collapse = 'geneSymbol')
res2 <- res
set.seed(123)
res2$best.p <- res2$best.p * runif(nrow(res2))
res2$direction[sample(1:nrow(res), 500)] <- res2$direction[sample(1:nrow(res), 500)]

# 3. Create a list of results data.frames from multiple contrasts (allResults)
allResults <- ct.regularizeContrasts(
    dflist = list('Experiment1' = res[1:1500, ], 'Experiment2' = res2[1:1900, ]), 
    collapse = 'geneSymbol'
)

# 4. Create a GeneSetDb object for pathway enrichment
if (requireNamespace("sparrow", quietly = TRUE)) {
    gs_df <- data.frame(
        collection = "my_collection",
        name = "my_geneset",
        feature_id = res$geneSymbol[1:50]
    )
    genesetdb <- sparrow::GeneSetDb(gs_df)
} else {
    # Fallback if sparrow is not available
    genesetdb <- list(collection = "my_collection", feature_id = res$geneSymbol[1:50])
}

# 5. Serialize objects to the working directory
# Saving both with and without .rds extension to ensure compatibility with the workflow's read expectations
saveRDS(resultsDF, "resultsDF.rds")
saveRDS(res2, "res2.rds")
saveRDS(allResults, "allResults.rds")
saveRDS(genesetdb, "genesetdb.rds")

saveRDS(resultsDF, "resultsDF.rds")
saveRDS(res2, "res2.rds")
saveRDS(allResults, "allResults.rds")
saveRDS(genesetdb, "genesetdb.rds")