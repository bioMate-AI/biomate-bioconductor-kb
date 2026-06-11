# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("MetaboCoreUtils")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(MetaboCoreUtils)

# Copy rti.txt from the package installation
rti_file <- system.file("retentionIndex", "rti.txt", package = "MetaboCoreUtils")
if (file.exists(rti_file)) {
    file.copy(rti_file, "rti.txt", overwrite = TRUE)
} else {
    # Fallback to vignette data if the file is not found
    rti <- data.frame(
        rtime = c(1.14, 1.18, 1.38, 2.11, 4.34, 5.92),
        rindex = c(100, 200, 300, 400, 500, 600)
    )
    write.table(rti, "rti.txt", sep = "\t", row.names = FALSE, quote = FALSE)
}

# Copy metabolites.txt from the package installation
metabolites_file <- system.file("retentionIndex", "metabolites.txt", package = "MetaboCoreUtils")
if (file.exists(metabolites_file)) {
    file.copy(metabolites_file, "metabolites.txt", overwrite = TRUE)
} else {
    # Fallback to vignette data if the file is not found
    rtime <- data.frame(
        name = c("VITAMIN D2", "SQUALENE", "4-COUMARATE", "NONANOATE", "ESTRADIOL-17ALPHA", "CAPRYLATE"),
        rtime = c(NA, 15.66, 6.26, 11.73, 10.27, 10.67)
    )
    write.table(rtime, "metabolites.txt", sep = "\t", row.names = FALSE, quote = FALSE)
}