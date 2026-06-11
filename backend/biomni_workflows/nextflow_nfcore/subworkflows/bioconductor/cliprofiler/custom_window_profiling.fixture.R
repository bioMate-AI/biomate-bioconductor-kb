# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("cliProfiler", "GenomicRanges", "rtracklayer")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(cliProfiler)
library(GenomicRanges)
library(rtracklayer)

testpath <- system.file("extdata", package = "cliProfiler")

# 1. peaks.rds
test_rds_path <- file.path(testpath, "test.rds")
if (file.exists(test_rds_path)) {
    file.copy(test_rds_path, "peaks.rds", overwrite = TRUE)
} else {
    test_gr <- GRanges(
        seqnames = "chr17", 
        ranges = IRanges(start = 28748198, end = 28748218), 
        strand = "+"
    )
    saveRDS(test_gr, "peaks.rds")
}

# 2. custom_annotation.gff3
test_gff3_path <- file.path(testpath, "annotation_test.gff3")
if (file.exists(test_gff3_path)) {
    file.copy(test_gff3_path, "custom_annotation.gff3", overwrite = TRUE)
} else {
    gff_gr <- GRanges(
        seqnames = "chr17", 
        ranges = IRanges(start = 28748000, end = 28749000), 
        strand = "+", 
        source = "HAVANA", 
        type = "gene", 
        ID = "ENSMUSG00000000001.1", 
        gene_id = "ENSMUSG00000000001.1", 
        gene_type = "protein_coding", 
        gene_name = "TestGene"
    )
    export.gff3(gff_gr, "custom_annotation.gff3")
}