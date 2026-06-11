# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ZygosityPredictor", "dplyr", "stringr", "GenomicRanges")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ZygosityPredictor)
library(dplyr)
library(stringr)
library(GenomicRanges)

# Copy BAM file and its index
bam_file <- system.file("extdata", "ZP_example.bam", package = "ZygosityPredictor")
if (file.exists(bam_file)) {
    file.copy(bam_file, "FILE_BAM", overwrite = TRUE)
    if (file.exists(paste0(bam_file, ".bai"))) {
        file.copy(paste0(bam_file, ".bai"), "FILE_BAM.bai", overwrite = TRUE)
    }
}

# Copy VCF file and its index
vcf_file <- system.file("extdata", "ZP_example_chr7.vcf.gz", package = "ZygosityPredictor")
if (file.exists(vcf_file)) {
    file.copy(vcf_file, "VCF", overwrite = TRUE)
    if (file.exists(paste0(vcf_file, ".tbi"))) {
        file.copy(paste0(vcf_file, ".tbi"), "VCF.tbi", overwrite = TRUE)
    }
}

# Load and save GRanges objects
data("GR_SCNA", package = "ZygosityPredictor")
saveRDS(GR_SCNA, "GR_SCNA")

data("GR_SOM_SMALL_VARS", package = "ZygosityPredictor")
saveRDS(GR_SOM_SMALL_VARS, "GR_SOM_SMALL_VARS")

data("GR_GERM_SMALL_VARS", package = "ZygosityPredictor")
saveRDS(GR_GERM_SMALL_VARS, "GR_GERM_SMALL_VARS")

data("GR_GENE_MODEL", package = "ZygosityPredictor")
saveRDS(GR_GENE_MODEL, "GR_GENE_MODEL")

data("GR_HAPLOBLOCKS", package = "ZygosityPredictor")
saveRDS(GR_HAPLOBLOCKS, "GR_HAPLOBLOCKS")