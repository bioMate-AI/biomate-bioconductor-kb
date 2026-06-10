# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CHETAH", "SingleCellExperiment", "Matrix")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CHETAH)
library(SingleCellExperiment)
library(Matrix)

# Reproduce the vignette's data-preparation code
# Load CHETAH's internal datasets
data('headneck_ref')
data('input_mel')

# Extract the required components as per the vignette
# input_counts: counts_melanoma
input_counts_obj <- assay(input_mel)

# input_tsne: tsne_melanoma
input_tsne_obj <- reducedDim(input_mel)

# ref_counts: counts_hn
ref_counts_obj <- assay(headneck_ref)

# ref_ct: celltypes_hn
ref_ct_obj <- headneck_ref$celltypes

# Serialize objects to .rds files, as the workflow's read_input_file prioritizes .rds
saveRDS(input_counts_obj, "input_counts.rds")
saveRDS(input_tsne_obj, "input_tsne.rds")
saveRDS(ref_counts_obj, "ref_counts.rds")
saveRDS(ref_ct_obj, "ref_ct.rds")