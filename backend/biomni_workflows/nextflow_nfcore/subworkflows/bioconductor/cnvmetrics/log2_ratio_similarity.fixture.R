# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CNVMetrics")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CNVMetrics)

extdata_files <- list.files(system.file("extdata", package="CNVMetrics"), pattern="mousePairedOrganoids\\.txt$", full.names=TRUE)

if (length(extdata_files) > 0 && file.exists(extdata_files[1])) {
    calls <- read.table(extdata_files[1], header=TRUE, sep="\t")
} else {
    calls <- data.frame(
        ID = c("mT3", "mT3", "mT3", "mT3", "mT3", "mT3"),
        chr = c("chr1", "chr2", "chr3", "chr4", "chr5", "chr5"),
        start = c(3527630, 3549740, 3536051, 3734693, 3575586, 111373751),
        end = c(195471971, 182113224, 160039680, 156508116, 111373751, 114262563),
        log2ratio = c(0.143253158, 0.008638116, 0.032630258, -0.026741963, -0.018519856, 0.226961493),
        state = c("NEUTRAL", "NEUTRAL", "NEUTRAL", "NEUTRAL", "NEUTRAL", "AMPLIFICATION")
    )
}

write.table(calls, file="copy_number_log2.txt", sep="\t", quote=FALSE, row.names=FALSE)