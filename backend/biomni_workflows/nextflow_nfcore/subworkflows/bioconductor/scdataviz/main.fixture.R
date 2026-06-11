# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("scDataviz", "flowCore")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(scDataviz)
library(flowCore)

# Discover FCS files shipped with flowCore to use as a substitute for the external GitHub data
filelist <- list.files(system.file("extdata", package = "flowCore"), 
                       pattern = "\\.fcs$|\\.B08$", 
                       full.names = TRUE)

# Limit to 2 files for a quick test fixture
if (length(filelist) > 2) {
    filelist <- filelist[1:2]
}

# Construct metadata matching the vignette's structure
metadata <- data.frame(
  sample = paste0("Sample", seq_along(filelist)),
  group = rep(c("Healthy", "Disease"), length.out = length(filelist)),
  treatment = rep(c("Unstim", "CD46"), length.out = length(filelist)),
  row.names = filelist,
  stringsAsFactors = FALSE
)

# Serialize to the declared input files
saveRDS(filelist, "filelist.rds")
saveRDS(metadata, "metadata.rds")