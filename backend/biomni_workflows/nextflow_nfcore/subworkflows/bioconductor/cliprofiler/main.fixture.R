# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("cliProfiler", "rtracklayer", "GenomicRanges")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(cliProfiler)
library(rtracklayer)
library(GenomicRanges)

testpath <- system.file("extdata", package = "cliProfiler")

# 1. Prepare peaks.rds
test_rds_file <- file.path(testpath, "test.rds")
if (file.exists(test_rds_file)) {
    test_gr <- readRDS(test_rds_file)
    saveRDS(test_gr, "peaks.rds")
} else {
    # Fallback synthetic GRanges if the file is missing
    test_gr <- GRanges(seqnames = "chr1", ranges = IRanges(start = seq(100, 1000, by = 100), width = 20))
    saveRDS(test_gr, "peaks.rds")
}

# 2. Prepare annotation.gff3
test_gff3_file <- file.path(testpath, "annotation_test.gff3")
if (file.exists(test_gff3_file)) {
    file.copy(test_gff3_file, "annotation.gff3", overwrite = TRUE)
} else {
    # Fallback synthetic GFF3 if the file is missing
    gr_annot <- GRanges(
        seqnames = "chr1", 
        ranges = IRanges(start = 1, end = 2000), 
        strand = "+", 
        type = "gene", 
        ID = "gene1", 
        gene_id = "gene1", 
        gene_type = "protein_coding"
    )
    export.gff3(gr_annot, "annotation.gff3")
}