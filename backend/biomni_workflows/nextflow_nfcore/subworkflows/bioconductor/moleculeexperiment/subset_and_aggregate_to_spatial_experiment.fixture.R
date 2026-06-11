library(MoleculeExperiment)

# 1. Create 'me' using the Xenium example from the vignette
repoDir <- system.file("extdata", package = "MoleculeExperiment")
xeniumDir <- paste0(repoDir, "/xenium_V1_FF_Mouse_Brain")
me <- readXenium(xeniumDir, keepCols = "essential")

# Save 'me' to both possible filenames checked by the workflow
saveRDS(me, "me.rds")
saveRDS(me, "me")

# 2. Create 'meMerscope' using the toy data example from the vignette as a fallback,
# or actual Merscope data if present in extdata.
moleculesDf <- data.frame(
  sample_id = rep(c("sample1", "sample2"), times = c(30, 20)),
  features = rep(c("gene1", "gene2"), times = c(20, 30)),
  x_coords = runif(50),
  y_coords = runif(50)
)

boundariesDf <- data.frame(
  sample_id = rep(c("sample1", "sample2"), times = c(16, 6)),
  cell_id = rep(
    c("cell1", "cell2", "cell3", "cell4", "cell1", "cell2"),
    times = c(4, 4, 4, 4, 3, 3)
  ),
  vertex_x = c(
    0, 0.5, 0.5, 0, 0.5, 1, 1, 0.5, 0, 0.5, 0.5, 0, 0.5, 1, 1, 0.5,
    0, 1, 0, 0, 1, 1
  ),
  vertex_y = c(
    0, 0, 0.5, 0.5, 0, 0, 0.5, 0.5, 0.5, 0.5, 1, 1, 0.5, 0.5, 1, 1,
    0, 1, 1, 0, 0, 1
  )
)

moleculesMEList <- dataframeToMEList(
  moleculesDf, 
  dfType = "molecules", 
  assayName = "detected", 
  sampleCol = "sample_id", 
  factorCol = "features", 
  xCol = "x_coords", 
  yCol = "y_coords"
)

boundariesMEList <- dataframeToMEList(
  boundariesDf, 
  dfType = "boundaries", 
  assayName = "cell", 
  sampleCol = "sample_id", 
  factorCol = "cell_id", 
  xCol = "vertex_x", 
  yCol = "vertex_y"
)

toyME <- MoleculeExperiment(
  molecules = moleculesMEList,
  boundaries = boundariesMEList
)

# Attempt to find Merscope data in extdata, otherwise use toyME
merscope_dirs <- list.files(system.file("extdata", package = "MoleculeExperiment"), 
                            pattern = "merscope", ignore.case = TRUE, full.names = TRUE)

if (length(merscope_dirs) > 0 && exists("readMerscope")) {
  meMerscope <- readMerscope(merscope_dirs[1], keepCols = "essential")
} else {
  meMerscope <- toyME
}

# Save 'meMerscope' to both possible filenames checked by the workflow
saveRDS(meMerscope, "meMerscope.rds")
saveRDS(meMerscope, "meMerscope")