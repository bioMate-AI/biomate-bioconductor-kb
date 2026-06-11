# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Rtpca", "TPP", "dplyr")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(Rtpca)
library(TPP)
library(dplyr)

# 1. Prepare tpp_data.RData
data("hdacTR_smallExample", package = "TPP")
set.seed(123)
random_proteins <- sample(hdacTR_data[[1]]$gene_name, 300)
hdacTR_data_fil <- lapply(hdacTR_data, function(temp_df){
    dplyr::filter(temp_df, gene_name %in% random_proteins)
})
trData <- tpptrImport(configTable = hdacTR_config, data = hdacTR_data_fil)
save(trData, file = "tpp_data.RData")

# 2. Prepare ppi_annotations.csv
data("string_ppi_df", package = "Rtpca")
write.csv(string_ppi_df, file = "ppi_annotations.csv", row.names = FALSE)

# 3. Prepare complex_annotations.csv
data("ori_et_al_complexes_df", package = "Rtpca")
write.csv(ori_et_al_complexes_df, file = "complex_annotations.csv", row.names = FALSE)