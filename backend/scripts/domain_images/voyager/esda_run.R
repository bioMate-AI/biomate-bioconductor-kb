#!/usr/bin/env Rscript
# Minimal-correct Voyager Visium ESDA.
# Baked into bioc-domain-spatial:3.20-deps at /opt/biomate/voyager/esda_run.R.
#
# Loads a 10X Visium SpatialFeatureExperiment (SFEData built-in example, or a
# user .rds), does QC + log-normalization + HVG selection, builds the Visium
# spatial neighborhood graph, and computes univariate Moran's I (global spatial
# autocorrelation) per HVG. Emits an SFE .rds, a Moran's I table, a QC table,
# two plots, and a JSON summary.
#
# Method reference: the canonical Voyager Visium ESDA vignette
# (McKellar et al. 2021 mouse skeletal muscle; Moses & Pachter 2023 Nat Methods).

suppressWarnings(suppressPackageStartupMessages({
  library(SpatialFeatureExperiment)
  library(SpatialExperiment)
  library(Voyager)
  library(SFEData)
  library(scater)
  library(scran)
  library(ggplot2)
}))

## ---- tiny arg parser (--key value) ------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
getarg <- function(flag, default = NULL) {
  i <- which(args == flag)
  if (length(i) && i < length(args)) return(args[i + 1L])
  default
}
opt <- list(
  sfe_dataset = getarg("--sfe_dataset", "McKellarMuscleData"),
  sfe_rds     = getarg("--sfe_rds", "null"),
  min_counts  = as.numeric(getarg("--min_counts", "100")),
  n_hvgs      = as.integer(getarg("--n_hvgs", "200")),
  max_spots   = as.integer(getarg("--max_spots", "2000")),
  sample_id   = getarg("--sample_id", "sample")
)
cat("[esda] options:\n"); str(opt)

## ---- 1. load the SFE --------------------------------------------------------
if (!is.null(opt$sfe_rds) && nchar(opt$sfe_rds) && opt$sfe_rds != "null" &&
    file.exists(opt$sfe_rds)) {
  cat("[esda] loading user SFE from", opt$sfe_rds, "\n")
  sfe <- readRDS(opt$sfe_rds)
} else {
  cat("[esda] loading SFEData example:", opt$sfe_dataset, "\n")
  fn <- get(opt$sfe_dataset, envir = asNamespace("SFEData"))
  sfe <- fn()
}
stopifnot(is(sfe, "SpatialFeatureExperiment"))
cat("[esda] loaded SFE:", nrow(sfe), "genes x", ncol(sfe), "spots\n")

## ---- 2. QC: keep in-tissue spots, filter low-count spots ---------------------
if ("in_tissue" %in% colnames(colData(sfe))) {
  sfe <- sfe[, colData(sfe)$in_tissue]
  cat("[esda] kept", ncol(sfe), "in-tissue spots\n")
}
# per-spot total counts
tot <- colSums(counts(sfe))
colData(sfe)$nCounts <- tot
colData(sfe)$nGenes  <- colSums(counts(sfe) > 0)
keep_spot <- tot >= opt$min_counts
sfe <- sfe[, keep_spot]
cat("[esda] kept", ncol(sfe), "spots with >=", opt$min_counts, "counts\n")

# drop all-zero genes
sfe <- sfe[rowSums(counts(sfe)) > 0, ]

# subsample to bound runtime/cost
if (ncol(sfe) > opt$max_spots) {
  set.seed(7)
  sel <- sort(sample(seq_len(ncol(sfe)), opt$max_spots))
  sfe <- sfe[, sel]
  cat("[esda] subsampled to", ncol(sfe), "spots (max_spots cap)\n")
}

qc <- data.frame(
  spot_id = colnames(sfe),
  nCounts = colData(sfe)$nCounts,
  nGenes  = colData(sfe)$nGenes
)
write.csv(qc, "qc_metrics.csv", row.names = FALSE)

## ---- 3. normalize -----------------------------------------------------------
sfe <- logNormCounts(sfe)

## ---- 4. HVG selection -------------------------------------------------------
gv <- modelGeneVar(sfe)
n_hvg <- min(opt$n_hvgs, nrow(sfe))
hvgs <- getTopHVGs(gv, n = n_hvg)
cat("[esda] selected", length(hvgs), "HVGs\n")

# resolve a gene-symbol column for readable output if present
sym_col <- NULL
if ("symbol" %in% colnames(rowData(sfe))) sym_col <- "symbol"

## ---- 5. spatial neighborhood graph ------------------------------------------
sample_ids <- unique(colData(sfe)$sample_id)
graph_ok <- TRUE
tryCatch({
  colGraph(sfe, "visium") <- findVisiumGraph(sfe)
}, error = function(e) {
  cat("[esda] findVisiumGraph failed (", conditionMessage(e),
      ") — falling back to k-NN graph\n")
  colGraph(sfe, "visium") <<- findSpatialNeighbors(sfe, method = "knearneigh", k = 6)
})

## ---- 6. univariate Moran's I ------------------------------------------------
sfe <- runUnivariate(
  sfe, type = "moran", features = hvgs,
  colGraphName = "visium",
  swap_rownames = sym_col
)

rd <- rowData(sfe)
moran_col <- grep("^moran", colnames(rd), value = TRUE)[1]
moran_vals <- rd[hvgs, moran_col]
gene_label <- if (!is.null(sym_col)) rd[hvgs, sym_col] else hvgs
moran <- data.frame(
  gene       = hvgs,
  symbol     = gene_label,
  morans_I   = as.numeric(moran_vals)
)
moran <- moran[order(-moran$morans_I), ]
write.csv(moran, "univariate_moran.csv", row.names = FALSE)
cat("[esda] wrote Moran's I for", nrow(moran), "genes; top:\n")
print(utils::head(moran, 5))

saveRDS(sfe, "sfe_esda.rds")

## ---- 7. plots ---------------------------------------------------------------
topn <- utils::head(moran, 20)
topn$symbol <- factor(topn$symbol, levels = rev(topn$symbol))
p1 <- ggplot(topn, aes(x = symbol, y = morans_I)) +
  geom_col(fill = "#2c7fb8") + coord_flip() +
  labs(title = "Top spatially autocorrelated genes (Moran's I)",
       x = NULL, y = "Moran's I") + theme_bw()
ggsave("moran_top_genes.png", p1, width = 6, height = 6, dpi = 120)

top_gene <- moran$gene[1]
p2 <- tryCatch(
  plotSpatialFeature(sfe, features = top_gene, colGeometryName = "spotPoly",
                     swap_rownames = sym_col) +
    ggtitle(paste0("Spatial expression: ", moran$symbol[1])),
  error = function(e) {
    cat("[esda] plotSpatialFeature failed (", conditionMessage(e),
        ") — using nCounts scatter fallback\n")
    xy <- spatialCoords(sfe)
    df <- data.frame(x = xy[, 1], y = xy[, 2], v = colData(sfe)$nCounts)
    ggplot(df, aes(x, y, color = v)) + geom_point(size = 0.8) +
      scale_color_viridis_c() + coord_equal() +
      labs(title = "Spatial nCounts", color = "nCounts") + theme_bw()
  }
)
ggsave("spatial_feature.png", p2, width = 6, height = 6, dpi = 120)

## ---- 8. JSON summary --------------------------------------------------------
summary <- list(
  sample_id     = opt$sample_id,
  dataset       = if (opt$sfe_rds != "null") opt$sfe_rds else opt$sfe_dataset,
  n_spots       = ncol(sfe),
  n_genes       = nrow(sfe),
  n_hvgs        = length(hvgs),
  min_counts    = opt$min_counts,
  top_gene      = moran$symbol[1],
  top_morans_I  = round(moran$morans_I[1], 4),
  median_morans_I = round(stats::median(moran$morans_I, na.rm = TRUE), 4),
  Voyager_version = as.character(packageVersion("Voyager"))
)
writeLines(jsonlite::toJSON(summary, auto_unbox = TRUE, pretty = TRUE),
           "esda_summary.json")
cat("[esda] DONE. Outputs: sfe_esda.rds, univariate_moran.csv, qc_metrics.csv,",
    "moran_top_genes.png, spatial_feature.png, esda_summary.json\n")
