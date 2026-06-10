# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("FuseSOM", "SingleCellExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(FuseSOM)
library(SingleCellExperiment)

# Load the dataset provided by the package
data("risom_dat", package = "FuseSOM")

# Define the markers of interest as per the vignette
risomMarkers <- c('CD45','SMA','CK7','CK5','VIM','CD31','PanKRT','ECAD',
                  'Tryptase','MPO','CD20','CD3','CD8','CD4','CD14','CD68','FAP',
                  'CD36','CD11c','HLADRDPDQ','P63','CD44')

# Rename the phenotype column
names(risom_dat)[names(risom_dat) == 'manual_gating_phenotype'] <- 'CellType'

# Create the SingleCellExperiment object
colDat <- risom_dat[, setdiff(colnames(risom_dat), risomMarkers), drop = FALSE]
sce_obj <- SingleCellExperiment(assays = list(counts = t(risom_dat)), colData = colDat)

# Serialize the object to the expected input file
saveRDS(sce_obj, "sce.rds")