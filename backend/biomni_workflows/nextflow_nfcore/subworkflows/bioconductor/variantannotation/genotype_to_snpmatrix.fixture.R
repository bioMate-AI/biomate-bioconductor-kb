# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("VariantAnnotation")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(VariantAnnotation)

extdata_dir <- system.file("extdata", package="VariantAnnotation")

# Copy chr22.vcf.gz and its index to the working directory
chr22_src <- list.files(extdata_dir, pattern="chr22\\.vcf\\.gz$", full.names=TRUE, recursive=TRUE)
if (length(chr22_src) > 0) {
    file.copy(chr22_src[1], "chr22.vcf.gz", overwrite=TRUE)
}

chr22_tbi_src <- list.files(extdata_dir, pattern="chr22\\.vcf\\.gz\\.tbi$", full.names=TRUE, recursive=TRUE)
if (length(chr22_tbi_src) > 0) {
    file.copy(chr22_tbi_src[1], "chr22.vcf.gz.tbi", overwrite=TRUE)
}

# Copy gl_chr1.vcf to the working directory
gl_src <- list.files(extdata_dir, pattern="gl_chr1\\.vcf$", full.names=TRUE, recursive=TRUE)
if (length(gl_src) > 0) {
    file.copy(gl_src[1], "gl_chr1.vcf", overwrite=TRUE)
}