# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("scGPS")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(scGPS)

data("day_2_cardio_cell_sample", package = "scGPS")
day2 <- day_2_cardio_cell_sample
mixedpop1 <- new_scGPS_object(
    ExpressionMatrix = day2$dat2_counts, 
    GeneMetadata = day2$dat2geneInfo, 
    CellMetadata = day2$dat2_clusters
)

data("day_5_cardio_cell_sample", package = "scGPS")
day5 <- day_5_cardio_cell_sample
mixedpop2 <- new_scGPS_object(
    ExpressionMatrix = day5$dat5_counts, 
    GeneMetadata = day5$dat5geneInfo, 
    CellMetadata = day5$dat5_clusters
)

data("training_gene_sample", package = "scGPS")
genes_obj <- training_gene_sample
genes <- genes_obj$Merged_unique

saveRDS(mixedpop1, "mixedpop1")
saveRDS(mixedpop2, "mixedpop2")
saveRDS(genes, "genes")