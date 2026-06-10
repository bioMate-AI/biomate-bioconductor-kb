# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("biodbHmdb")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(biodbHmdb)

# Generate synthetic intensity.csv
intensity_data <- data.frame(
    Feature = c("HMDB0000001", "HMDB0000002", "HMDB0000005", "HMDB0000008", "HMDB0000010"),
    Sample1 = c(10.5, 20.1, 5.3, 8.9, 15.2),
    Sample2 = c(11.2, 19.8, 6.1, 8.5, 14.9),
    Sample3 = c(15.3, 25.4, 8.2, 12.1, 20.5),
    Sample4 = c(14.8, 24.9, 7.9, 11.8, 19.8)
)
write.csv(intensity_data, "intensity.csv", row.names = FALSE)

# Generate synthetic coldata.csv
coldata <- data.frame(
    Sample = c("Sample1", "Sample2", "Sample3", "Sample4"),
    Condition = c("Control", "Control", "Treatment", "Treatment")
)
write.csv(coldata, "coldata.csv", row.names = FALSE)