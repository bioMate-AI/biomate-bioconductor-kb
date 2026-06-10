# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("PRONE")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(PRONE)

# Attempt to locate the files using the package's built-in helper
data_path <- tryCatch(readPRONE_example("tuberculosis_protein_intensities.csv"), error = function(e) "")
md_path <- tryCatch(readPRONE_example("tuberculosis_metadata.csv"), error = function(e) "")

# Fallback to system.file if the helper fails or returns an empty path
if (!file.exists(data_path)) {
    data_path <- system.file("extdata", "tuberculosis_protein_intensities.csv", package="PRONE")
}
if (!file.exists(md_path)) {
    md_path <- system.file("extdata", "tuberculosis_metadata.csv", package="PRONE")
}

# Copy or synthesize tuberculosis_protein_intensities.csv
if (file.exists(data_path)) {
    file.copy(data_path, "tuberculosis_protein_intensities.csv", overwrite = TRUE)
} else {
    # Create synthetic data matching the expected columns in the vignette
    data <- data.frame(
        Protein.IDs = c("P1", "P2", "P3", "P4", "P5"),
        Gene.names = c("G1", "G2", "G3", "G4", "G5"),
        Sample.1 = c(10.1, 20.2, 30.3, 40.4, 50.5),
        Sample.2 = c(15.5, 25.5, 35.5, 45.5, 55.5),
        Sample.3 = c(12.2, 22.2, 32.2, 42.2, 52.2)
    )
    write.csv(data, "tuberculosis_protein_intensities.csv", row.names = FALSE)
}

# Copy or synthesize tuberculosis_metadata.csv
if (file.exists(md_path)) {
    file.copy(md_path, "tuberculosis_metadata.csv", overwrite = TRUE)
} else {
    # Create synthetic metadata matching the expected columns in the vignette
    md <- data.frame(
        Column = c("Sample.1", "Sample.2", "Sample.3"),
        Group = c("ref", "test", "test"),
        Pool = c("Batch1", "Batch1", "Batch1"),
        Label = c("S1", "S2", "S3")
    )
    write.csv(md, "tuberculosis_metadata.csv", row.names = FALSE)
}