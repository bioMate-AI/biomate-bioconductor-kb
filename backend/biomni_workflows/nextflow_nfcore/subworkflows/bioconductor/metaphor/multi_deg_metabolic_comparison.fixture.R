# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("MetaPhOR")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(MetaPhOR)

copy_fixture <- function(filename) {
    src <- list.files(system.file("extdata", package = "MetaPhOR"), 
                      pattern = paste0("^", filename, "$"), 
                      recursive = TRUE, 
                      full.names = TRUE)
    if (length(src) > 0) {
        file.copy(src[1], filename, overwrite = TRUE)
    } else {
        stop(paste("Could not find", filename, "in MetaPhOR extdata"))
    }
}

copy_fixture("BRCA_DEGS.csv")
copy_fixture("OVCA_Scores.csv")
copy_fixture("PRAD_Scores.csv")