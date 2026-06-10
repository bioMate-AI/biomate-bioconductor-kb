# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("beer", "dplyr", "ggplot2")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(beer)
library(dplyr)
library(ggplot2)

data_path <- system.file("extdata/sim_data.rds", package = "beer")
if (file.exists(data_path)) {
    sim_data <- readRDS(data_path)
    saveRDS(sim_data, "sim_data.rds")
    saveRDS(sim_data, "PhIPData_object.rds")
} else {
    stop("sim_data.rds not found in beer package")
}