# Fixture for branch_point_analysis.nf — needs chol_attributes, hep_attributes
# (outputs of TrajectoryGeometry::analyseSingleCellTrajectory) plus the
# pseudotimes that produced them.
.fx_deps <- c("TrajectoryGeometry")
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
  library(TrajectoryGeometry)
})

# Synthesize PCA-space embedding + per-lineage pseudotimes, then run
# analyseSingleCellTrajectory for each lineage so the *_attributes
# objects have the real shape branch_point_analysis.nf consumes.
set.seed(42)
n_cells <- 200; n_pcs <- 11
cell_ids <- sprintf("Cell_%04d", seq_len(n_cells))
hep_idx  <- seq_len(n_cells %/% 2)
chol_idx <- seq.int(n_cells %/% 2 + 1L, n_cells)

M <- matrix(rnorm(n_cells * n_pcs, sd = 0.5), nrow = n_cells, ncol = n_pcs,
            dimnames = list(cell_ids, sprintf("PC%d", seq_len(n_pcs))))
hep_pt  <- seq(0, 1, length.out = length(hep_idx))
chol_pt <- seq(0, 1, length.out = length(chol_idx))
M[hep_idx,  1] <- M[hep_idx,  1] + 3 * hep_pt
M[hep_idx,  2] <- M[hep_idx,  2] + 1 * hep_pt
M[chol_idx, 1] <- M[chol_idx, 1] - 2 * chol_pt
M[chol_idx, 3] <- M[chol_idx, 3] + 3 * chol_pt

hep_pseudo_time  <- setNames(hep_pt,  cell_ids[hep_idx])
chol_pseudo_time <- setNames(chol_pt, cell_ids[chol_idx])

# Run analyseSingleCellTrajectory on each lineage to produce realistic
# attributes objects (the same shape branch_point_analysis.nf reads).
make_attrs <- function(idx, pt) {
  tryCatch(
    TrajectoryGeometry::analyseSingleCellTrajectory(
      M[idx, , drop = FALSE], pt,
      randomizationParams = c("byPermutation", "permuteWithin"),
      statistic = "mean",
      N = 50
    ),
    error = function(e) {
      message("analyseSingleCellTrajectory failed (", conditionMessage(e),
              ") — falling back to a minimal attributes shape.")
      list(
        sphericalData = list(distances = runif(length(idx))),
        pValue        = 0.05,
        randomDistances = runif(50)
      )
    }
  )
}
hep_attributes  <- make_attrs(hep_idx,  hep_pt)
chol_attributes <- make_attrs(chol_idx, chol_pt)

saveRDS(chol_attributes,  "chol_attributes.rds")
saveRDS(hep_attributes,   "hep_attributes.rds")
saveRDS(chol_pseudo_time, "chol_pseudo_time.rds")
saveRDS(hep_pseudo_time,  "hep_pseudo_time.rds")

cat("Fixture wrote:",
    paste(list.files(pattern = "\\.rds$"), collapse = ", "),
    "\n")
