# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Seurat", "SeuratObject", "tibble", "dplyr")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(Seurat)
library(SeuratObject)
library(tibble)
library(dplyr)

data("pbmc_small")

features <- pbmc_small |>
    FindAllMarkers(only.pos = TRUE, verbose = FALSE) |>
    group_by(cluster) |>
    dplyr::slice(1:6) |>
    dplyr::select(cluster, gene)

pbmc_small[[DefaultAssay(pbmc_small)]][[]] <- pbmc_small[[DefaultAssay(pbmc_small)]][[]] |>
    rownames_to_column("gene") |> 
    left_join(features, by = "gene") |> 
    column_to_rownames("gene")

saveRDS(pbmc_small, "pbmc_small.rds")