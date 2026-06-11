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

# 1. Prepare TPP data using the vignette's example
data("hdacTR_smallExample", package = "TPP")

# Filter data to speed up computations as done in the vignette
set.seed(123)
random_proteins <- sample(hdacTR_data[[1]]$gene_name, 300)
hdacTR_data_fil <- lapply(hdacTR_data, function(temp_df){
  filter(temp_df, gene_name %in% random_proteins)
})

# Import data using TPP package
trData <- tpptrImport(configTable = hdacTR_config, data = hdacTR_data_fil)

# Split into control and treatment datasets based on the vignette's contrast setup
tpp_control_data <- trData[1:2]
tpp_treatment_data <- trData[3:4]

# Save to RData files
save(tpp_control_data, file = "tpp_control_data.RData")
save(tpp_treatment_data, file = "tpp_treatment_data.RData")

# 2. Prepare PPI annotations
data("string_ppi_df", package = "Rtpca")

# Save to CSV
write.csv(string_ppi_df, file = "ppi_annotations.csv", row.names = FALSE)