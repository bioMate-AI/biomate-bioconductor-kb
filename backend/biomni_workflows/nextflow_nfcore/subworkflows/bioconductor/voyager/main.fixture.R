# [biomate-fx-deps] SFEData ships small example SpatialFeatureExperiment
# objects (and the underlying tissue images) Voyager was built against.
# Install both SFEData and SpatialFeatureExperiment if missing — they're
# not in the bioc-domain-transcriptomics:3.20 base layer.
.fx_deps <- c("SFEData", "SpatialFeatureExperiment", "SpatialExperiment", "Voyager", "scater", "scran", "pheatmap")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly = TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly = TRUE)) {
    install.packages("BiocManager", repos = "https://cloud.r-project.org")
  }
  bin <- tryCatch(
    sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker",
            BiocManager::version()),
    error = function(e) NULL
  )
  suppressMessages(tryCatch(
    BiocManager::install(.fx_miss, update = FALSE, ask = FALSE, site_repository = bin),
    error = function(e) BiocManager::install(.fx_miss, update = FALSE, ask = FALSE)
  ))
}

suppressPackageStartupMessages({
  library(SFEData)
  library(SpatialFeatureExperiment)
})

# Load the smallest SFE example Voyager's spatial-stat functions support:
# the 10x Visium mouse skeletal-muscle dataset. The "small" variant is ~6000
# spots which still takes too long for Voyager's full pipeline (Moran's I +
# bivariate Lee's L + MULTISPATI PCA) inside the harness's 300s budget.
# Aggressively subsample to ~400 spots and 800 genes so runtime is bounded.
sfe_full <- SFEData::McKellarMuscleData("small")
set.seed(7)
spot_keep <- sample(seq_len(ncol(sfe_full)), min(400, ncol(sfe_full)))
gene_keep <- sample(seq_len(nrow(sfe_full)), min(800, nrow(sfe_full)))
sfe <- sfe_full[gene_keep, spot_keep]

# Voyager's workflow expects the SFE itself plus a low-resolution tissue
# image (jpeg). The image is embedded in the SFE's imgData; extract and
# write it out so the .nf load_input("tissue_lowres_5a.jpeg") finds it.
saveRDS(sfe, "sfe.rds")

img_data <- imgData(sfe)
if (nrow(img_data) > 0) {
  # First image in the SFE is the low-res Visium tissue png/jpeg.
  img <- img_data$data[[1]]
  raster <- SpatialExperiment::imgRaster(img)
  # imgRaster returns a magick-image; write as JPEG to match the .nf
  # declared input name.
  if (requireNamespace("magick", quietly = TRUE)) {
    magick::image_write(raster, path = "tissue_lowres_5a.jpeg", format = "jpeg")
  } else if (requireNamespace("jpeg", quietly = TRUE)) {
    # raster is a magick::image; convert to array for jpeg::writeJPEG
    arr <- as.integer(raster)
    jpeg::writeJPEG(arr / 255, target = "tissue_lowres_5a.jpeg", quality = 0.85)
  } else {
    # last-resort placeholder so the workflow loads SOMETHING
    bm <- matrix(runif(100 * 100), 100, 100)
    if (requireNamespace("png", quietly = TRUE)) {
      png::writePNG(bm, "tissue_lowres_5a.jpeg")
    } else {
      writeBin(charToRaw("\xff\xd8\xff\xe0"), "tissue_lowres_5a.jpeg")
    }
  }
} else {
  # SFE example has no embedded image; synthesize a minimal valid JPEG.
  if (requireNamespace("jpeg", quietly = TRUE)) {
    jpeg::writeJPEG(matrix(runif(64 * 64), 64, 64), target = "tissue_lowres_5a.jpeg")
  }
}

cat("Fixture wrote:",
    paste(list.files(pattern = "^(sfe|tissue_lowres)"), collapse = ", "),
    "\n")
cat("  sfe spots:", ncol(sfe), "\n")
cat("  sfe genes:", nrow(sfe), "\n")
