# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ggspavis", "STexampleData", "scater", "scran")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ggspavis)
library(STexampleData)
library(scater)
library(scran)

# Load example datasets from STexampleData
spe_xen <- STexampleData::Janesick_breastCancer_Xenium_rep1()
spe_cos <- STexampleData::CosMx_lungCancer()
spe_mer <- STexampleData::MERSCOPE_ovarianCancer()
spe_sta <- STexampleData::STARmapPLUS_mouseBrain()

# Calculate reduced dimensions for spe_sta as per the vignette
spe_sta <- logNormCounts(spe_sta)
dec <- modelGeneVar(spe_sta)
hvg <- getTopHVGs(dec, n=3e3)
spe_sta <- runPCA(spe_sta, subset_row=hvg)
spe_sta <- runUMAP(spe_sta, dimred="PCA")

# Serialize the objects to the required input files
saveRDS(spe_xen, "spe_xen.rds")
saveRDS(spe_cos, "spe_cos.rds")
saveRDS(spe_mer, "spe_mer.rds")
saveRDS(spe_sta, "spe_sta.rds")