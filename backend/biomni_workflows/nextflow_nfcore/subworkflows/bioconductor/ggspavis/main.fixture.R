# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ggspavis", "STexampleData", "SpatialExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ggspavis)
library(STexampleData)
library(SpatialExperiment)

# 1. spe_slide
spe_slide <- STexampleData::SlideSeqV2_mouseHPC()
saveRDS(spe_slide, file = "spe_slide.rds")

# 2. spe_vm
spe_vm <- STexampleData::Visium_mouseCoronal()
saveRDS(spe_vm, file = "spe_vm.rds")

# 3. spe
spe <- STexampleData::Visium_humanDLPFC()
saveRDS(spe, file = "spe.rds")

# 4. vhd8
vhd8_success <- FALSE
if (requireNamespace("OSTA.data", quietly = TRUE) && requireNamespace("VisiumIO", quietly = TRUE)) {
    try({
        id <- "VisiumHD_HumanColon_Oliveira"
        pa <- OSTA.data::OSTA.data_load(id)
        td <- tempfile()
        dir.create(td)
        unzip(pa, exdir=td)
        vhd8_obj <- VisiumIO::TENxVisiumHD(spacerangerOut=td, processing="filtered", format="h5", images="lowres", bin_size="008")
        vhd8 <- BiocIO::import(vhd8_obj)
        vhd8_success <- TRUE
    }, silent = TRUE)
}

if (!vhd8_success) {
    # Fallback mock object if OSTA.data is unavailable or fails offline
    counts_mat <- matrix(rpois(100 * 100, lambda = 5), nrow = 100, ncol = 100)
    rownames(counts_mat) <- paste0("Gene", 1:100)
    colnames(counts_mat) <- paste0("Spot", 1:100)
    
    spatial_coords <- matrix(runif(200, min = 0, max = 1000), ncol = 2)
    colnames(spatial_coords) <- c("pxl_col_in_fullres", "pxl_row_in_fullres")
    rownames(spatial_coords) <- colnames(counts_mat)
    
    vhd8 <- SpatialExperiment(
        assays = list(counts = counts_mat),
        spatialCoords = spatial_coords
    )
    rowData(vhd8)$Symbol <- rownames(vhd8)
}
saveRDS(vhd8, file = "vhd8.rds")