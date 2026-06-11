# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("igvR")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(igvR)

# Generate regions.bed using data from the igvR package
narrowPeaksFile <- system.file(package="igvR", "extdata", "ctcf-gata2", "gata2-region-macs2-narrowPeaks.RData")
if (file.exists(narrowPeaksFile)) {
    tbl.pk <- get(load(narrowPeaksFile))
    # Write as a standard BED file (chrom, start, end, score)
    write.table(tbl.pk, "regions.bed", sep="\t", quote=FALSE, row.names=FALSE, col.names=FALSE)
} else {
    # Fallback synthetic BED file
    regions <- data.frame(
        chrom = c("chr10", "chr10", "chr11"),
        start = c(127910682, 128075644, 127965327),
        end = c(127910864, 128075811, 127965489),
        score = c(27, 89, 70)
    )
    write.table(regions, "regions.bed", sep="\t", quote=FALSE, row.names=FALSE, col.names=FALSE)
}

# Generate coldata.csv
coldata <- data.frame(
    sample = c("sample1", "sample2", "sample3", "sample4"),
    condition = c("control", "control", "treatment", "treatment"),
    replicate = c(1, 2, 1, 2)
)
write.csv(coldata, "coldata.csv", row.names=FALSE)