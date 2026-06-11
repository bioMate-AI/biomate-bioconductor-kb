# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("crisprViz", "BSgenome.Hsapiens.UCSC.hg38", "crisprDesign")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(crisprViz)
library(BSgenome.Hsapiens.UCSC.hg38)
library(crisprDesign) # For removeRepeats and findOverlaps

# 1. Reproduce the vignette's data-preparation code

# Prepare bsgenome object
bsgenome <- BSgenome.Hsapiens.UCSC.hg38

# Prepare geneModel object (using mmp7GeneModel as it's used with the filtered guideSet)
data("mmp7GeneModel", package="crisprViz")
geneModel <- mmp7GeneModel

# Prepare repeats object
data("repeats", package="crisprViz")
repeats <- repeats

# Prepare cage object
data("cage", package="crisprViz")
cage <- cage

# Prepare dnase object
data("dnase", package="crisprViz")
dnase <- dnase

# Prepare guideSet object (derived from mmp7GuideSet, filtered as in vignette section 3.3)
data("mmp7GuideSet", package="crisprViz")
filteredGuideSet <- crisprDesign::removeRepeats(mmp7GuideSet, gr.repeats=repeats)
filteredGuideSet <- filteredGuideSet[!filteredGuideSet$hasSNP]
overlaps <- findOverlaps(filteredGuideSet, dnase, ignore.strand=TRUE)
guideSet <- filteredGuideSet[queryHits(overlaps)]

# 2. Serialize objects to .rds files
saveRDS(guideSet, "guideSet.rds")
saveRDS(geneModel, "geneModel.rds")
saveRDS(bsgenome, "bsgenome.rds")
saveRDS(repeats, "repeats.rds")
saveRDS(cage, "cage.rds")
saveRDS(dnase, "dnase.rds")