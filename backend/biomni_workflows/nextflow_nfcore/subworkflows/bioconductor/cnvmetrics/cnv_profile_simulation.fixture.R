# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CNVMetrics")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CNVMetrics)

data.dir <- system.file("extdata", package="CNVMetrics")
cnv.file <- file.path(data.dir, "mousePairedOrganoids.txt")

if (file.exists(cnv.file)) {
    calls <- read.table(cnv.file, header=TRUE, sep="\t")
    # Subset to a single reference sample
    ref_calls <- calls[calls$ID == calls$ID[1], ]
    write.table(ref_calls, file="reference_sample.txt", sep="\t", quote=FALSE, row.names=FALSE)
} else {
    # Fallback synthetic data if the file is not found
    ref_calls <- data.frame(
        ID = rep("ref1", 3),
        chr = c("chr1", "chr1", "chr2"),
        start = c(1000, 5000, 2000),
        end = c(4999, 10000, 8000),
        log2ratio = c(0.1, 0.8, -0.5),
        state = c("NEUTRAL", "AMPLIFICATION", "DELETION")
    )
    write.table(ref_calls, file="reference_sample.txt", sep="\t", quote=FALSE, row.names=FALSE)
}