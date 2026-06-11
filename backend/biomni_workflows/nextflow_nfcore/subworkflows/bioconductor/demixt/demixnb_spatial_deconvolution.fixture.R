# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DeMixT")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DeMixT)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# Load the primary example dataset
data("test.data.2comp")

# The vignette loads pre-computed results for res.GS.
# We locate this file within the package's installed directory.
res_GS_path <- system.file("Res_2comp", "res.GS.RData", package = "DeMixT")

# Check if the file exists. If not, we would need to run DeMixT_GS,
# but for strict vignette reproduction, loading is preferred if the file is distributed.
if (!file.exists(res_GS_path)) {
  stop("res.GS.RData not found at expected path. Cannot reproduce vignette data prep.")
}

# Load the pre-computed res.GS object
load(res_GS_path)

# 2. Extract and serialize objects to declared input files

# count_matrix: corresponds to data.Y from test.data.2comp
count_matrix <- test.data.2comp$data.Y
saveRDS(count_matrix, "count_matrix.rds")

# barcode_mixed: corresponds to the column names of data.Y (mixed samples)
barcode_mixed <- colnames(test.data.2comp$data.Y)
saveRDS(as.character(barcode_mixed), "barcode_mixed.rds")

# barcode_reference: corresponds to the column names of data.N1 (reference samples)
barcode_reference <- colnames(test.data.2comp$data.N1)
saveRDS(as.character(barcode_reference), "barcode_reference.rds")

# top_genes: corresponds to the gene names selected by DeMixT_GS
top_genes <- res.GS$gene.name
saveRDS(as.character(top_genes), "top_genes.rds")