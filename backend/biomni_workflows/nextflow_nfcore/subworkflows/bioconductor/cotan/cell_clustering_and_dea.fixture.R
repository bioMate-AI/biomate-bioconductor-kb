# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("COTAN", "zeallot")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(COTAN)
library(zeallot)
conflicted::conflict_prefer("%<-%", "zeallot")

dataDir <- tempdir()
outDir <- dataDir

data(raw.dataset)
rawDataset <- raw.dataset

cond <- "mouse_cortex_E17.5"
obj <- COTAN(raw = rawDataset)
obj <- initializeMetaDataset(
  obj,
  GEO = "GSM2861514_example",
  sequencingMethod = "Drop_seq",
  sampleCondition = cond
)

data(vignette.cells.origin)
obj <- addCondition(obj, condName = "origin", conditions = vignette.cells.origin)

cellsSizeThr <- 6000L
obj <- addElementToMetaDataset(obj, "Cells size threshold", cellsSizeThr)
cellsToRem <- getCells(obj)[getCellsSize(obj) > cellsSizeThr]
obj <- dropGenesCells(obj, cells = cellsToRem)

genesSizeHighThr <- 3000L
obj <- addElementToMetaDataset(obj, "Num genes high threshold", genesSizeHighThr)
cellsToRem <- getCells(obj)[getNumExpressedGenes(obj) > genesSizeHighThr]
obj <- dropGenesCells(obj, cells = cellsToRem)

genesSizeLowThr <- 500L
obj <- addElementToMetaDataset(obj, "Num genes low threshold", genesSizeLowThr)
cellsToRem <- getCells(obj)[getNumExpressedGenes(obj) < genesSizeLowThr]
obj <- dropGenesCells(obj, cells = cellsToRem)

c(mitPlot, mitSizes) %<-% mitochondrialPercentagePlot(obj, genePrefix = "^mt-", condName = "origin")
mitPercThr <- 3.5
obj <- addElementToMetaDataset(obj, "Mitoc. perc. threshold", mitPercThr)
cellsToRem <- rownames(mitSizes)[mitSizes[["mit.percentage"]] > mitPercThr]
obj <- dropGenesCells(obj, cells = cellsToRem)

obj <- addElementToMetaDataset(obj, "Num drop B group", 0L)
obj <- clean(obj)

c(pcaCellsPlot, pcaCellsData, genesPlot, UDEPlot, nuPlot, zoomedNuPlot) %<-% cleanPlots(obj)

cellsToRem <- rownames(pcaCellsData)[pcaCellsData[["groups"]] == "B"]
obj <- dropGenesCells(obj, cells = cellsToRem)
obj <- addElementToMetaDataset(obj, "Num drop B group", 1L)

udeLowThr <- 0.34
obj <- addElementToMetaDataset(obj, "Low UDE cells' threshold", udeLowThr)
obj <- estimateNuLinear(obj)
cellsToRem <- getCells(obj)[getNu(obj) < udeLowThr]
obj <- dropGenesCells(obj, cells = cellsToRem)

obj <- clean(obj)
c(pcaCellsPlot, pcaCellsData, genesPlot, UDEPlot, nuPlot, zoomedNuPlot) %<-% cleanPlots(obj)

saveRDS(obj, file = "obj.RDS")
saveRDS(vignette.cells.origin, file = "vignette.split.clusters.RDS")