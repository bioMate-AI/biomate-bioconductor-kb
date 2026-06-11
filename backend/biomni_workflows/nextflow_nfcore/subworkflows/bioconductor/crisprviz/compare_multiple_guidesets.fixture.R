# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("crisprViz", "BSgenome.Hsapiens.UCSC.hg38")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(crisprViz)
library(BSgenome.Hsapiens.UCSC.hg38)

# Load precomputed GuideSet and gene model objects from crisprViz package
data("cas9GuideSet", package="crisprViz")
data("cas12aGuideSet", package="crisprViz")
data("ltn1GeneModel", package="crisprViz")

# Define output file names
cas9_file <- "cas9GuideSet.rds"
cas12a_file <- "cas12aGuideSet.rds"
genemodel_file <- "ltn1GeneModel.rds"
bsgenome_file <- "BSgenome.Hsapiens.UCSC.hg38.rds"

# Serialize objects to RDS files
saveRDS(cas9GuideSet, file = cas9_file)
saveRDS(cas12aGuideSet, file = cas12a_file)
saveRDS(ltn1GeneModel, file = genemodel_file)
saveRDS(BSgenome.Hsapiens.UCSC.hg38, file = bsgenome_file)