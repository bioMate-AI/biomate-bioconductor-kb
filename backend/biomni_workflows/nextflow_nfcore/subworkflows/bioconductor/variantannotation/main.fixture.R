# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("VariantAnnotation", "TxDb.Hsapiens.UCSC.hg19.knownGene", "BSgenome.Hsapiens.UCSC.hg19", "PolyPhen.Hsapiens.dbSNP131")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages({
    library(VariantAnnotation)
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    library(BSgenome.Hsapiens.UCSC.hg19)
    library(PolyPhen.Hsapiens.dbSNP131)
})

# 1. chr22.vcf.gz
vcf_file <- system.file("extdata", "chr22.vcf.gz", package="VariantAnnotation")
if (file.exists(vcf_file)) {
    file.copy(vcf_file, "chr22.vcf.gz", overwrite = TRUE)
    tbi_file <- paste0(vcf_file, ".tbi")
    if (file.exists(tbi_file)) {
        file.copy(tbi_file, "chr22.vcf.gz.tbi", overwrite = TRUE)
    }
} else {
    vcf_files <- list.files(system.file("extdata", package="VariantAnnotation"), 
                            pattern="chr22\\.vcf\\.gz$", recursive=TRUE, full.names=TRUE)
    if (length(vcf_files) > 0) {
        file.copy(vcf_files[1], "chr22.vcf.gz", overwrite = TRUE)
        if (file.exists(paste0(vcf_files[1], ".tbi"))) {
            file.copy(paste0(vcf_files[1], ".tbi"), "chr22.vcf.gz.tbi", overwrite = TRUE)
        }
    }
}

# 2. TxDb.Hsapiens.UCSC.hg19.knownGene
saveRDS(TxDb.Hsapiens.UCSC.hg19.knownGene, "TxDb.Hsapiens.UCSC.hg19.knownGene")

# 3. BSgenome.Hsapiens.UCSC.hg19
saveRDS(BSgenome.Hsapiens.UCSC.hg19, "BSgenome.Hsapiens.UCSC.hg19")

# 4. PolyPhen.Hsapiens.dbSNP131
saveRDS(PolyPhen.Hsapiens.dbSNP131, "PolyPhen.Hsapiens.dbSNP131")