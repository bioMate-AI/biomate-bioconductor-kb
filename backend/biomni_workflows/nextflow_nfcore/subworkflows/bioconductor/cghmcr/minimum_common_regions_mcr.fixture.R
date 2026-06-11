# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("limma", "cghMCR", "DNAcopy")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
require("limma")
require("cghMCR") # Required for system.file("sampleData", package = "cghMCR")

arrayFiles  <- list.files(system.file("sampleData", package = "cghMCR"),
     full.names = TRUE, pattern = "TCGA")

rawData <- read.maimages(arrayFiles, source = "agilent", columns =
    list(R = "rMedianSignal", G = "gMedianSignal", Rb = "rBGMedianSignal",
    Gb = "gBGMedianSignal"), annotation = c("Row", "Col", "ControlType",
    "ProbeName", "GeneName", "SystematicName", "PositionX", "PositionY",
    "gIsFeatNonUnifOL", "rIsFeatNonUnifOL", "gIsBGNonUnifOL", "rIsBGNonUnifOL",
    "gIsFeatPopnOL", "rIsFeatPopnOL", "gIsBGPopnOL", "rIsBGPopnOL",
    "rIsSaturated", "gIsSaturated"), names = basename(arrayFiles))

rawData$design <- c(-1, -1, -1)

ma <- normalizeWithinArrays(backgroundCorrect(rawData, method = "minimum"), method = "loess")

chrom <- gsub("chr([0-9XY]+):.*", "\\1", ma$genes[, "SystematicName"])
dropMe <- c(which(!chrom %in% c(1:22, "X", "Y")), which(ma$genes[, "ControlType"] != 0))

require(DNAcopy, quietly = TRUE)
set.seed(25)
cna <- CNA(ma$M[-dropMe, ],
    gsub("chr([0-9XY]+):.*", "\\1", ma$genes[-dropMe, "SystematicName"]),
    as.numeric(gsub(".*:([0-9]+)-.*", "\\1",
      ma$genes[-dropMe, "SystematicName"])),
    data.type = "logratio", sampleid = colnames(ma$M))
segData <- segment(smooth.CNA(cna))

saveRDS(segData, "segData.rds")