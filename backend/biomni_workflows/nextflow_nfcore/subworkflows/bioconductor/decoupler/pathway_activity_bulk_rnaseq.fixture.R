# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("decoupleR", "dplyr")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(decoupleR)
library(dplyr)

bk_data_path <- list.files(system.file("extdata", package = "decoupleR"), 
                           pattern = "bk_data\\.rds$", 
                           recursive = TRUE, 
                           full.names = TRUE)

if (length(bk_data_path) > 0 && file.exists(bk_data_path[1])) {
    file.copy(bk_data_path[1], "bk_data.rds", overwrite = TRUE)
} else {
    data <- get_toy_data()
    saveRDS(data, "bk_data.rds")
}