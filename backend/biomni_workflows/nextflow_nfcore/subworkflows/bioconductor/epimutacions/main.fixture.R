# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("epimutacions", "minfi", "minfiData")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(epimutacions)
library(minfi)
library(minfiData)

# 1. baseDir: directory containing raw case IDAT files and SampleSheet.csv
baseDir <- "baseDir"
dir.create(baseDir, showWarnings = FALSE)

# Try to use epimutacionsData if available and populated
has_epi_data <- requireNamespace("epimutacionsData", quietly = TRUE)
if (has_epi_data) {
    baseDir_pkg <- system.file("extdata", package = "epimutacionsData")
    if (baseDir_pkg != "" && length(list.files(baseDir_pkg)) > 0) {
        file.copy(list.files(baseDir_pkg, full.names = TRUE), baseDir, recursive = TRUE)
    }
}

# Fallback to minfiData if baseDir is still empty
if (length(list.files(baseDir)) == 0) {
    minfi_base <- system.file("extdata", package = "minfiData")
    file.copy(list.files(minfi_base, full.names = TRUE), baseDir, recursive = TRUE)
}

# 2. reference_panel: RGChannelSet object containing reference/control samples
data(RGsetEx, package = "minfiData")
reference_panel <- RGsetEx
saveRDS(reference_panel, "reference_panel.rds")
saveRDS(reference_panel, "reference_panel.rds")

# 3. methy: GenomicRatioSet containing preprocessed case and control samples
data(MsetEx, package = "minfiData")
methy <- ratioConvert(MsetEx)
methy <- mapToGenome(methy)

# The vignette filters by status: case_samples <- methy[,methy$status == "case"]
methy$status <- rep(c("case", "control"), length.out = ncol(methy))

saveRDS(methy, "methy.rds")
saveRDS(methy, "methy.rds")