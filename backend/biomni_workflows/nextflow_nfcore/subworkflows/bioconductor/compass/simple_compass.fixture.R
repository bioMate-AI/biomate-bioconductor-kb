# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("COMPASS")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(COMPASS)

example_data_path <- system.file("extdata", "SimpleCOMPASSExamples.csv", package = "COMPASS")

if (file.exists(example_data_path)) {
    file.copy(example_data_path, "SimpleCOMPASSExamples.csv", overwrite = TRUE)
} else {
    # Fallback in case the file is missing from the installation
    df <- data.frame(
        Sample = paste0("S", 1:10),
        Group = rep(c("Control", "Treatment"), each = 5),
        Count = rpois(10, 100)
    )
    write.csv(df, "SimpleCOMPASSExamples.csv", row.names = FALSE)
}