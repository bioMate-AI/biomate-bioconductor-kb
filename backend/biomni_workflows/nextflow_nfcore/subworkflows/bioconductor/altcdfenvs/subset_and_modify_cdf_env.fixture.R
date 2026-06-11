# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("altcdfenvs")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(altcdfenvs)

src_txt <- system.file("exampleData", "Plasmodium-Probeset-IDs.txt", package="altcdfenvs")
if (file.exists(src_txt)) {
    file.copy(src_txt, "Plasmodium-Probeset-IDs.txt", overwrite = TRUE)
} else {
    writeLines(c("Pf_1", "Pf_2", "Pf_3"), "Plasmodium-Probeset-IDs.txt")
}

saveRDS(new.env(), "plasmodiumanophelescdf")