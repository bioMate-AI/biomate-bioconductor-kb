# Real user-style input for SPOTlight deconvolution:
#   sce.rds - a single-cell RNA-seq REFERENCE (SingleCellExperiment) with raw
#             counts and a per-cell cell-type annotation in colData$free_annotation
#   spe.rds - a spatial transcriptomics dataset (SpatialExperiment) with raw
#             counts over the SAME genes and 2D spatial coordinates.
#
# These are exactly the two objects a user supplies to SPOTlight (a scRNA-seq
# reference + a Visium-style spatial matrix). We synthesise them with a genuine
# cell-type structure (distinct marker programs per type) so marker detection,
# NMF training and deconvolution all produce meaningful, input-derived output.
# No ExperimentHub / package demo data is downloaded.

suppressPackageStartupMessages({
  library(SingleCellExperiment)
  library(SpatialExperiment)
})

set.seed(2024)

n_types  <- 4
n_genes  <- 300
cell_types <- paste0("CellType", seq_len(n_types))

# Per-type marker programs: each type strongly over-expresses a disjoint block
# of ~25 marker genes; the rest are shared background.
gene_ids <- sprintf("Gene%03d", seq_len(n_genes))
marker_block <- split(seq_len(n_types * 25), rep(seq_len(n_types), each = 25))

# ---- Single-cell reference (SCE) ----
cells_per_type <- 80
n_cells <- n_types * cells_per_type
cell_type_vec <- rep(cell_types, each = cells_per_type)

sim_counts <- function(type_idx, ncell) {
    base <- matrix(rpois(n_genes * ncell, lambda = 0.5), nrow = n_genes)
    mk <- marker_block[[type_idx]]
    base[mk, ] <- base[mk, ] + matrix(rpois(length(mk) * ncell, lambda = 12),
                                      nrow = length(mk))
    base
}
sce_counts <- do.call(cbind, lapply(seq_len(n_types),
                                    function(k) sim_counts(k, cells_per_type)))
rownames(sce_counts) <- gene_ids
colnames(sce_counts) <- sprintf("cell%04d", seq_len(n_cells))

sce <- SingleCellExperiment(assays = list(counts = sce_counts))
sce$free_annotation <- cell_type_vec
colLabels(sce) <- factor(cell_type_vec)
saveRDS(sce, "sce.rds")

# ---- Spatial dataset (SPE) ----
# Build spots as mixtures of cell types so deconvolution is meaningful.
n_spots <- 100
spot_counts <- matrix(0L, nrow = n_genes, ncol = n_spots)
for (s in seq_len(n_spots)) {
    props <- as.numeric(rmultinom(1, size = 1, prob = runif(n_types)))
    mix <- sample(seq_len(n_types), 1, prob = runif(n_types) + 0.1)
    spot_counts[, s] <- as.integer(rowSums(sim_counts(mix, 8)))
}
rownames(spot_counts) <- gene_ids
colnames(spot_counts) <- sprintf("spot%04d", seq_len(n_spots))

coords <- cbind(
    x = rep(seq_len(10), times = 10),
    y = rep(seq_len(10), each = 10)
)[seq_len(n_spots), , drop = FALSE]

spe <- SpatialExperiment(
    assays = list(counts = spot_counts),
    spatialCoords = as.matrix(coords)
)
saveRDS(spe, "spe.rds")

# emit each declared input under BOTH bare-token and .rds names so the harness
# collects the serialized object under whatever name the workflow stages it as.
for (b in c("sce", "spe")) {
    rds <- paste0(b, ".rds")
    if (file.exists(rds) && !file.exists(b)) file.copy(rds, b, overwrite = TRUE)
}
