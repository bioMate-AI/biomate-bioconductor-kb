# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("faers")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(faers)

# Locate and copy the shipped faers_ascii_2004q1.zip to the working directory
zip_candidates <- list.files(system.file(package = "faers"), pattern = "faers_ascii_2004q1\\.zip$", recursive = TRUE, full.names = TRUE)
if (length(zip_candidates) > 0) {
    file.copy(zip_candidates[1], "faers_ascii_2004q1.zip", overwrite = TRUE)
} else {
    # Fallback synthetic creation if the file is not found
    dummy_txt <- "DEMO04Q1.txt"
    writeLines(c("primaryid$caseid$age", "1$1$50", "2$2$60"), dummy_txt)
    zip("faers_ascii_2004q1.zip", dummy_txt)
    unlink(dummy_txt)
}

# Locate and copy the shipped standardized_data.rds to the working directory
rds_candidates <- list.files(system.file(package = "faers"), pattern = "standardized_data\\.rds$", recursive = TRUE, full.names = TRUE)
if (length(rds_candidates) > 0) {
    file.copy(rds_candidates[1], "standardized_data.rds", overwrite = TRUE)
} else {
    # Fallback synthetic creation if the file is not found
    dummy_data <- data.frame(
        primaryid = c("1", "2"),
        caseid = c("1", "2"),
        drugname = c("DRUG A", "DRUG B"),
        outc_cod = c("DE", "HO")
    )
    saveRDS(dummy_data, "standardized_data.rds")
}