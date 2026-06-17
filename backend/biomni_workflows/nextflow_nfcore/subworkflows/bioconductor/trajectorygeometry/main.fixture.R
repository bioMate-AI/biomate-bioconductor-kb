# Synthesize fixture inputs without loading TrajectoryGeometry.
# The .nf workflow installs TrajectoryGeometry itself (its .bm_deps loop
# calls install.packages from Bioconductor repos). The fixture only needs
# to produce inputs in the shape the package functions expect.
#
# Shape per TrajectoryGeometry vignette:
#   single_cell_matrix: numeric matrix cells × principal-components
#                       (the PCA-space embedding samplePath operates on)
#   chol_pseudo_time / hep_pseudo_time:
#                       named numeric vectors, names = cell ids, values
#                       in [0, 1] pseudotime, one per lineage subset

set.seed(42)
n_cells <- 200
n_pcs   <- 11
cell_ids <- sprintf("Cell_%04d", seq_len(n_cells))

hep_idx  <- seq_len(n_cells %/% 2)
chol_idx <- seq.int(n_cells %/% 2 + 1L, n_cells)

# Two lineages, each with its own directional drift in PC1+PC2 / PC1+PC3.
M <- matrix(rnorm(n_cells * n_pcs, sd = 0.5), nrow = n_cells, ncol = n_pcs,
            dimnames = list(cell_ids, sprintf("PC%d", seq_len(n_pcs))))
hep_pt  <- seq(0, 1, length.out = length(hep_idx))
chol_pt <- seq(0, 1, length.out = length(chol_idx))
M[hep_idx,  1] <- M[hep_idx,  1] + 3 * hep_pt
M[hep_idx,  2] <- M[hep_idx,  2] + 1 * hep_pt
M[chol_idx, 1] <- M[chol_idx, 1] - 2 * chol_pt
M[chol_idx, 3] <- M[chol_idx, 3] + 3 * chol_pt

single_cell_matrix <- M
hep_pseudo_time    <- setNames(hep_pt,  cell_ids[hep_idx])
chol_pseudo_time   <- setNames(chol_pt, cell_ids[chol_idx])

saveRDS(single_cell_matrix, "single_cell_matrix.rds")
saveRDS(chol_pseudo_time,   "chol_pseudo_time.rds")
saveRDS(hep_pseudo_time,    "hep_pseudo_time.rds")

cat("Fixture wrote:",
    paste(list.files(pattern = "\\.rds$"), collapse = ", "),
    "\n")
cat("  single_cell_matrix:", nrow(single_cell_matrix), "x", ncol(single_cell_matrix), "\n")
cat("  hep_pseudo_time   :", length(hep_pseudo_time),  "cells\n")
cat("  chol_pseudo_time  :", length(chol_pseudo_time), "cells\n")
