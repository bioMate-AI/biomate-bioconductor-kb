# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CNVMetrics")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CNVMetrics)

# Locate the example dataset from the package
extdata_files <- list.files(
    system.file("extdata", package="CNVMetrics"), 
    pattern="mousePairedOrganoids.txt", 
    recursive=TRUE, 
    full.names=TRUE
)

if (length(extdata_files) > 0 && file.exists(extdata_files[1])) {
    # Read the existing file
    calls <- read.table(extdata_files[1], header=TRUE, sep="\t")
} else {
    # Fallback to synthetic data matching the vignette's structure
    calls <- data.frame(
        ID = c("mT3", "mT3", "mT3", "mM6", "mM6"),
        chr = c("chr1", "chr2", "chr5", "chr1", "chr5"),
        start = c(3527630, 3549740, 111373751, 3527630, 111373751),
        end = c(195471971, 182113224, 114262563, 195471971, 114262563),
        log2ratio = c(0.143253158, 0.008638116, 0.226961493, 0.102, 0.250),
        state = c("NEUTRAL", "NEUTRAL", "AMPLIFICATION", "NEUTRAL", "AMPLIFICATION")
    )
}

# Write the required input file for the workflow
write.table(
    calls, 
    file="copy_number_calls.txt", 
    sep="\t", 
    quote=FALSE, 
    row.names=FALSE
)